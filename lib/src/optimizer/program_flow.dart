import 'package:dartc/interop.dart' show NativeCompoundType;
import 'package:dartc/ir.dart';

import 'flow_state.dart';
import 'flow_memory.dart';
import 'flow_value.dart';
import 'integer_range.dart';
import 'loop_ranges.dart';
import 'memory_layout.dart';
import 'program_call_facts.dart';

/// One actual invocation, with all semantic entry arguments.
typedef FlowEntry = ({FunctionTarget target, List<FlowValue> arguments});

/// Joint execution, value and storage facts for one immutable source graph.
///
/// Reached suspendable bodies must first be normalized into ordinary semantic
/// IR; a completion value is never the public Future or generator result.
/// Internal calls carry their actual arguments and point state. Only explicitly
/// open entries admit arbitrary values. A replacement graph needs a new solver.
final class ProgramFlow(
  final IrProgram program,
  Iterable<FlowEntry> entries, {
  Iterable<FunctionTarget> openEntries = const [],
  Iterable<FunctionTarget> escapingReturns = const [],

  /// Raw ABI entries used only when their declared callback addresses escape.
  Map<NativeCallbackTarget, FunctionTarget> nativeEntries = const {},
  final FlowMemoryLayout? memoryLayout,

  /// Ordinary target body reporting a retained allocation's failure.
  final FunctionTarget? allocationFailure,

  /// The trusted runtime entry returning fresh managed storage or throwing.
  final FunctionTarget? managedAllocator,

  /// Fixed native regions returned by zero-argument external getters.
  /// Bytes describe the real entry state; null bytes are unknown. Getters must
  /// return the same nonzero address throughout this execution context.
  Map<FunctionTarget, List<int?>> initialMemory = const {},
}) {
  late final Map<FunctionTarget, FlowMemoryBinding> _externalMemory;
  late final _cellStorages = {
    for (final declaration in program.classes)
      declaration.type: ?declaration.cellStorage,
  };
  final _nativeEntries = Map<NativeCallbackTarget, FunctionTarget>.unmodifiable(
    nativeEntries,
  );
  final _entries = <FlowEntry>[];
  final _openEntries = <FunctionTarget>{};
  final _escapingReturns = <FunctionTarget>{};
  final _escapedCalls = <Object, _Activation>{};
  final _roots = <FunctionTarget, _Activation>{};
  final _calls = <_Activation>{};
  final _inputs = <_ContextKey, Set<_Activation>>{};
  final _inputIdentities = <(FunctionTarget, int), _InputIdentity>{};
  final _ancestry = _CallAncestry();
  final _callSites = <(_Activation, Instruction, FunctionTarget), _CallSite>{};
  final _pending = <_Activation>{};
  bool _lostCaller = false;
  final _owners = <Object, FunctionTarget>{};
  final _cyclic = <FunctionTarget, Set<Block>>{};
  final _loops = <FunctionTarget, LoopRanges>{};
  final _liveness = <FunctionTarget, ValueLiveness>{};
  final _storageAccess = <FunctionTarget, FlowStorageAccess?>{};
  final _allocating = <FunctionTarget, bool>{};
  final _accessPlans = <FunctionTarget, _AccessPlan>{};
  final _receiverBounds = <ValueType, List<ClassType>>{};
  final _definitions = <FunctionTarget>{};
  FlowState? _externalState;
  final _escapingActivations = <_Activation>{};
  final _nativeActivations = <_Activation>{};
  final _nativeLookups = <_Activation>{};
  final _constructedReturns = <_Activation, FlowValue>{};
  ProgramFlowFacts? _facts;
  final _exceptionSources = Expando<Map<Object, FlowState>>();

  this {
    _externalMemory = {
      for (final entry in initialMemory.entries)
        entry.key: (
          allocation: FlowObject(DirectCall(entry.key, []), this),
          memory: FlowMemory.bytes(entry.value),
        ),
    };
    for (final target in _externalMemory.keys) {
      final body = program.implementationOf(target);
      if (target.signature != FunctionType(.integer, []) ||
          body is! IrExternal ||
          body.memory is! UnchangedMemory) {
        throw ArgumentError(
          'Entry storage requires a non-mutating external address getter.',
        );
      }
    }
    if (managedAllocator case final target?
        when program.implementationOf(target) is! IrFunction ||
            target.signature != FunctionType(.integer, List.filled(5, ValueType.integer))) {
      throw ArgumentError('Managed allocation requires its supplied runtime body.');
    }
    if (allocationFailure case final target?
        when program.implementationOf(target) is! IrFunction ||
            target.kind != .function ||
            target.signature != FunctionType(.never, [])) {
      throw ArgumentError(
        'Allocation failure requires a supplied no-argument Never body.',
      );
    }
    for (final target in _nativeEntries.values) {
      if (program.implementationOf(target) is! IrFunction ||
          target.kind != .function ||
          target.typeParameters.isNotEmpty) {
        throw ArgumentError('A native entry requires a supplied raw ABI body.');
      }
    }
    for (final function in program.functions) {
      for (final block in function.blocks) {
        _owners[block] = function.target;
        for (final parameter in block.parameters) {
          _owners[parameter] = function.target;
        }
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          _owners[operation] = function.target;
        }
        for (final edge in block.successors) {
          _owners[edge] = function.target;
        }
      }
    }
    extend(
      entries: entries,
      openEntries: openEntries,
      escapingReturns: escapingReturns,
    );
  }

  /// Stable read-only facts; an effective extension invalidates this object.
  ProgramFlowFacts get facts => _facts ??= ProgramFlowFacts._(this);

  /// Adds invocations to this graph and resumes the same worklist.
  bool extend({
    Iterable<FlowEntry> entries = const [],
    Iterable<FunctionTarget> openEntries = const [],
    Iterable<FunctionTarget> escapingReturns = const [],
  }) {
    var changed = false;
    for (final entry in entries) {
      _validateEntry(entry);
      final target = entry.target.implementation;
      if (!_entries.any(
        (known) =>
            known.target == target &&
            _sameValues(known.arguments, entry.arguments),
      )) {
        final saved = (
          target: target,
          arguments: List<FlowValue>.unmodifiable(entry.arguments),
        );
        _entries.add(saved);
        _enterRoot(saved, open: false);
        changed = true;
      }
    }
    for (final source in openEntries) {
      final target = source.implementation;
      if (program.implementationOf(target) == null || target.kind == .closure) {
        throw ArgumentError('Open entry requires a supplied non-lexical body.');
      }
      if (_openEntries.add(target)) {
        _enterRoot((
          target: target,
          arguments: target.parameterTypes.map(FlowValue.unknown).toList(),
        ), open: true);
        changed = true;
      }
    }
    for (final source in [..._openEntries, ...escapingReturns]) {
      final target = source.implementation;
      if (!_roots.containsKey(target)) {
        throw ArgumentError(
          'An escaping return must belong to an actual entry.',
        );
      }
      if (_escapingReturns.add(target)) {
        _pending.add(_roots[target]!);
        changed = true;
      }
    }
    if (!changed) return false;
    _facts = null;
    var untilTrace = 0;
    while (_pending.isNotEmpty) {
      final activation = _pending.first;
      _pending.remove(activation);
      _evaluate(activation);
      if (_lostCaller && (--untilTrace <= 0 || _pending.isEmpty)) {
        _releaseDisconnected();
        _lostCaller = false;
        untilTrace = _pending.length;
      }
    }
    for (final activation in _activeContexts) {
      for (final entry in activation.storageViews.entries) {
        if (!entry.value) {
          throw StateError(
            'Unproven storage origin for ${entry.key.runtimeType} in '
            '${activation.body.target.name}.',
          );
        }
      }
    }
    return true;
  }

  Iterable<_Activation> get _activeContexts sync* {
    yield* _roots.values;
    yield* _calls;
    yield* _escapedCalls.values;
  }

  void _validateEntry(FlowEntry entry) {
    if (program.implementationOf(entry.target) == null ||
        entry.target.kind == .closure ||
        entry.arguments.length != entry.target.parameterTypes.length) {
      throw ArgumentError('Entry requires a supplied body and every argument.');
    }
    for (final (index, value) in entry.arguments.indexed) {
      if (value.objects.isNotEmpty ||
          value.managedBackings.isNotEmpty ||
          value.references.objects.isNotEmpty ||
          value.sources.isNotEmpty) {
        throw ArgumentError(
          'Entry allocations cannot cross analysis identities.',
        );
      }
      final type = entry.target.parameterTypes[index];
      if (value.types.any((actual) => !type.accepts(actual))) {
        throw ArgumentError(
          'Entry argument $index violates its semantic bound.',
        );
      }
      for (final address in [
        ...value.addresses,
        ...value.references.addresses,
      ]) {
        final target = switch (address.base) {
          StaticCallbackTarget(:final function) => function,
          ClosureCallbackTarget(:final lookup) => lookup,
          _ => null,
        };
        if (target != null && program.implementationOf(target) == null) {
          throw ArgumentError('Entry callback belongs to another program.');
        }
      }
      final pending = [...value.constants, ...value.references.constants];
      final visited = <Constant>{};
      while (pending.isNotEmpty) {
        final constant = pending.removeLast();
        if (!visited.add(constant)) continue;
        switch (constant) {
          case FunctionConstant(:final target, :final invocationEntry):
            if (program.implementationOf(
                  invocationEntry ?? target.implementation,
                ) ==
                null) {
              throw ArgumentError(
                'Entry function value belongs to another program.',
              );
            }
          case ObjectConstant(:final fields, :final payload):
            pending.addAll(fields.values);
            pending.addAll(payload);
          case RecordConstant(:final fields):
            pending.addAll(fields);
          case SequenceConstant(:final elements):
            pending.addAll(elements);
          case MapConstant(:final entries):
            for (final (key, value) in entries) {
              pending.addAll([key, value]);
            }
          case ScalarConstant() || TypeConstant():
            break;
        }
      }
    }
  }

  void _enterRoot(FlowEntry entry, {required bool open}) {
    if (entry.arguments.any((value) => value.isBottom)) return;
    final activation = _roots.putIfAbsent(
      entry.target,
      () => _Activation(program.implementationOf(entry.target)!),
    );
    activation.repeated |= open;
    activation.mergeEnvironment(const {});
    _supply(
      activation,
      entry.arguments.map((value) => value.asExternal()).toList(),
      open
          ? (_externalState ??= FlowState(
              program,
              memoryLayout: memoryLayout,
              externalMemory: _externalMemory,
            ))
          : FlowState(
              program,
              memoryLayout: memoryLayout,
              externalMemory: _externalMemory,
            ),
    );
  }

  bool _supply(
    _Activation activation,
    List<FlowValue> arguments,
    FlowState input,
  ) {
    if (arguments.length != activation.body.target.parameterTypes.length) {
      throw StateError('Invocation lost semantic arguments.');
    }
    input = input.copy(resetWrites: true);
    var changed = false;
    final signature = (program.executionShapes ?? ExecutionShapes.defaults)
        .entryOf(activation.body.target);
    for (final (index, value) in arguments.indexed) {
      final supplied = signature.parameters[index].isReference &&
              ExecutionShapes.forType(activation.body.target.parameterTypes[index]).isScalar &&
              value.unknownTypes.isNotEmpty && value.managedBackings.isEmpty
          ? value.withManagedBackings(const [], unknown: true) : value;
      final joined = activation.arguments[index].join(
        supplied,
        widen: activation.recursive,
      );
      changed |= joined != activation.arguments[index];
      activation.arguments[index] = joined;
    }
    if (activation.input == null) {
      activation.input = input.copy();
      changed = true;
    } else {
      changed =
          activation.input!.join(input, widen: activation.recursive) || changed;
    }
    if (changed) {
      activation._incomingIdentities = null;
      _pending.add(activation);
    }
    return changed;
  }

  FlowResult _invoke(
    _Activation caller,
    Block block,
    Instruction operation,
    FunctionTarget source,
    List<FlowValue> arguments,
    FlowState input, {
    Map<TypeParameterType, ValueType> environment = const {},
    bool checkAllArguments = false,
    // Helper invocations need not return the enclosing operation's value.
    FlowSource? resultSource,
    Object? exceptionalSource,
  }) {
    final alternatives = _exceptionSources[input];
    if (exceptionalSource == null &&
        alternatives != null &&
        alternatives.isNotEmpty &&
        operation is DirectCall &&
        program.implementationOf(source.implementation) is IrFunction) {
      var joined = _unreachable;
      final normal = <Object, FlowState>{};
      for (final arm in alternatives.entries) {
        final invoked = _invoke(caller, block, operation, source, arguments, arm.value,
            environment: environment, checkAllArguments: checkAllArguments,
            resultSource: resultSource, exceptionalSource: arm.key);
        joined = _joinResult(joined, invoked);
        if (invoked.normal case final state?) normal[arm.key] = state;
      }
      if (joined.normal case final state? when normal.isNotEmpty) {
        _exceptionSources[state] = normal;
      }
      return joined;
    }
    if (arguments.any((value) => value.isBottom)) return _unreachable;
    final target = source.implementation;
    if (operation case FunctionCall(target: final bound?)
        when bound != target &&
            !(operation.entryBinding?.entries.values.contains(target) ??
                false)) {
      throw StateError('Function value violates its proven call target.');
    }
    environment = {...environment};
    if (target.kind.hasReceiver && arguments.isNotEmpty) {
      final types = arguments.first.types.toSet();
      if (types.length == 1 &&
          types.single is ClassType &&
          (types.single as ClassType).asInstanceOf(target.owner!) != null) {
        environment = {
          ...target.environmentFor(types.single as ClassType),
          ...environment,
        };
      }
    }
    var failedCheck = false;
    final checks = checkAllArguments
        ? List.generate(target.signature.parameters.length, (index) => index)
        : target.covariantParameters;
    if (checks.isNotEmpty) {
      arguments = [...arguments];
      for (final index in checks) {
        final slot = target.argumentOffset + index;
        final expected = target.signature.parameters[index].substituteForFlow(
          environment,
        );
        final checked = arguments[slot].check(expected, runtimeTypes: true);
        failedCheck |= checked.mayFail;
        arguments[slot] = checked.value;
      }
      if (arguments.any((value) => value.isBottom)) {
        caller.operationEffects[operation] = {
          ...?caller.operationEffects[operation],
          Effect.mayThrow,
        };
        return FlowResult(exceptional: input.copy(), exception: _typeError);
      }
    }
    caller.targets.putIfAbsent(operation, () => {}).add(target);
    _definitions.add(target);
    final body = program.implementationOf(target);
    if (_deferredAllocationProjection(operation) &&
        (body is IrFunction ? _mayAllocate(body)
            : body is! IrExternal || body.effects.contains(Effect.allocates) ||
                body.effects.contains(Effect.callsUserCode))) {
      input = _allocationInput(caller, block, operation, arguments, input);
    }
    if (body is! IrFunction) {
      if (body is! IrExternal) {
        throw StateError(
          'Call analysis requires a body or an explicit external declaration: '
          '${target.library}::${target.owner == null ? '' : '${target.owner!.name}.'}'
          '${target.name}',
        );
      }
      caller.externalCalls.add(operation);
      final effects = body.effects;
      caller.externalEffects.putIfAbsent(operation, () => {}).addAll(effects);
      return _external(
        caller,
        block,
        operation,
        arguments,
        input,
        target.returnType.substituteForFlow(environment),
        effects: effects,
        memory: body.memory,
        capturesArguments: body.capturesArguments,
        returned: input.externalResult(target),
        allocationProjected: true,
      );
    }
    _ancestry.link(caller.body.target, target);
    final path = _recursivePath(caller, operation, target, arguments);
    final site = _callSites.putIfAbsent((
      caller,
      operation,
      target,
    ), () => _CallSite(caller, operation, target));
    final repeated =
        path.isNotEmpty ||
        caller.repeated ||
        _loopBlocks(caller.body).contains(block);
    final access = _accessForInput(body, arguments, input);
    final projected = input.project(arguments, access: access);
    var suppliedState = projected;
    final aliases = <(int, int)>[
      for (var i = 0; i < arguments.length; i++)
        for (var j = 0; j < i; j++)
          if (_equivalent(arguments[i], arguments[j])) (i, j),
    ];
    var plain = [for (final value in arguments) value.withSources(const [])];
    late final _Activation callee;
    _Activation? retired;
    _CallInput? binding;
    if (path.isNotEmpty) {
      callee = path.last;
    } else {
      final aliasKey = aliases.fold<Object?>(null, (key, pair) => (key, pair));
      final local = _ContextKey(
        target,
        const [],
        environment,
        site,
        repeated,
        exceptionalSource == null ? aliasKey : (exceptionalSource, aliasKey),
      );
      final invocation = site.contexts.putIfAbsent(
        local,
        () => _CallInput(plain, projected.copy()),
      );
      binding = invocation;
      invocation.join(plain, projected);
      final prepared = invocation.prepare(
        target,
        _inputIdentities,
        private: access != null && !access.exposed,
      );
      plain = prepared.arguments;
      suppliedState = prepared.state;
      final previous = invocation.activation;
      if (prepared.reset) {
        site.joined.remove(local);
        callee = _Activation(body);
      } else if (site.joined.contains(local)) {
        callee = previous!;
      } else {
        final keyState = suppliedState.copy()..retainSources((_) => false);
        final precise = _ContextKey(
          target,
          plain,
          environment,
          keyState.structuralKey,
          repeated,
          aliasKey,
        );
        if ((access == null || access.writes || previous?.recursive == true) &&
            previous != null &&
            previous.inputKey != precise) {
          // Effectful calls keep allocation identities as their inputs grow.
          // Recursive summaries are deliberately unindexed: retain their joined
          // call-site identity instead of repeatedly starting another SCC.
          site.joined.add(local);
          callee = previous.callSites.length == 1
              ? previous
              : _Activation(body);
          callee.shareInput = false;
        } else {
          callee =
              _inputs[precise]?.firstOrNull ??
              (previous != null && previous.callSites.length == 1
                  ? previous
                  : _Activation(body));
        }
      }
      _calls.add(callee);
      invocation.activation = callee;
      if (previous != null &&
          previous != callee &&
          !site.contexts.values.any((input) => input.activation == previous)) {
        previous.callSites.remove(site);
        caller.calls[operation]?.remove(previous);
        if (!caller.calls.values.any((calls) => calls.contains(previous))) {
          previous.readers.remove(caller);
        }
        retired = previous;
      }
    }
    if (repeated && !callee.repeated) {
      callee.repeated = true;
      _pending.add(callee);
    }
    if (path.isNotEmpty) {
      site.recursive = true;
      for (final cycle in path) {
        cycle.recursive = true;
        _indexInput(cycle);
        if (!cycle.repeated) {
          cycle.repeated = true;
          _pending.add(cycle);
        }
      }
      for (var i = 1; i < path.length; i++) {
        final parent = path[i], child = path[i - 1];
        for (final entry in parent.calls.entries) {
          if (entry.value.contains(child)) {
            _callSites[(parent, entry.key, child.body.target)]?.recursive =
                true;
          }
        }
      }
    }
    final environmentChanged = callee.mergeEnvironment(environment);
    if (environmentChanged) _pending.add(callee);
    caller.calls.putIfAbsent(operation, () => {}).add(callee);
    callee.readers.add(caller);
    callee.callSites.add(site);
    if (retired != null) _release(retired);
    final parameters = body.entry.parameters;
    final supplied = [
      for (final (i, value) in plain.indexed)
        value.withSources([
          FlowSource(parameters[i], callee),
          for (final (a, b) in aliases)
            if (a == i)
              FlowSource(parameters[b], callee)
            else if (b == i)
              FlowSource(parameters[a], callee),
        ]),
    ];
    final inputChanged = _supply(callee, supplied, suppliedState);
    if (inputChanged ||
        environmentChanged ||
        callee.inputKey?.repeated != callee.repeated) {
      _indexInput(callee);
    }

    FlowObject mapObject(FlowObject object) {
      if (object.site is NativeDataAddress ||
          object.site is ModuleObjectReference ||
          site.recursive) {
        return object;
      }
      if (binding?.originals[object] case final original?) return original;
      if (binding?.incomingIdentities.contains(object) ??
          callee.incomingIdentities.contains(object)) {
        return object;
      }
      final mapped = site.allocations.putIfAbsent(
        _allocationKey(object),
        () => FlowObject(
          object.site,
          _AllocationContext(object, site),
          type: object.type,
          variant: object.variant,
          cellStorage: object.cellStorage,
          storageView: object.storageView,
        ),
      );
      (mapped.activation as _AllocationContext).origins.add(object);
      return mapped;
    }

    FlowValue mapValue(
      FlowValue value, {
      bool normal = false,
      FlowState? exit,
    }) {
      final sources = <FlowSource>{};
      for (final source in value.sources) {
        if (!identical(source.activation, callee)) {
          sources.add(source);
          continue;
        }
        if (normal &&
            resultSource != null &&
            callee.returned.sources.contains(source)) {
          sources.add(resultSource);
        }
        if (source.value case final Instruction read
            when read is LoadField || read is ReadCell || read is LoadGlobal) {
          final operands = [
            for (final operand in read.inputs)
              operand is Constant
                  ? FlowValue.constant(operand)
                  : callee.values[operand] ?? const FlowValue.bottom(),
          ];
          if (exit?.preservesRead(read, operands) == true) {
            sources.addAll(
              input
                      .boundValueOf(
                        read,
                        operands
                            .map((value) => value.mapObjects(mapObject))
                            .toList(),
                      )
                      ?.sources ??
                  const <FlowSource>{},
            );
          }
        }
        final index = parameters.indexWhere(
          (parameter) => identical(parameter, source.value),
        );
        if (index >= 0) sources.addAll(arguments[index].sources);
      }
      return value.mapObjects(mapObject).withSources(sources);
    }

    FlowState? apply(_StateSummary? summary, {bool normal = false}) =>
        summary == null
        ? null
        : input.applySummary(
            summary.entry,
            summary.exit.project([
              ...supplied,
              ...suppliedState.allocations,
              callee.returned,
              callee.exception,
              if (!normal) callee.stackTrace,
            ]),
            mapObject: mapObject,
            mapValue: (value) =>
                mapValue(value, normal: normal, exit: summary.exit),
          );
    final thrownState = apply(callee.exceptionalSummary);
    final sourceExits = callee.exceptionSources;
    if (thrownState != null && sourceExits != null) {
      _exceptionSources[thrownState] = {
        for (final pair in sourceExits.entries) pair.key: apply(pair.value)!,
      };
    }
    final invoked = FlowResult(
      value: mapValue(callee.returned, exit: callee.normal),
      normal: apply(callee.normalSummary, normal: true),
      normalRanges: callee.normalParameterRanges.isEmpty
          ? const {}
          : {
              for (final entry in callee.normalParameterRanges.entries)
                for (final source in arguments[entry.key].sources)
                  if (identical(source.activation, caller))
                    source.value: entry.value,
            },
      exceptional: thrownState,
      allocationFailureOnly: !callee.hasSemanticFailure,
      exception: mapValue(callee.exception, exit: callee.exceptional),
      stackTrace: mapValue(callee.stackTrace, exit: callee.exceptional),
    );
    return failedCheck
        ? _joinResult(
            invoked,
            FlowResult(exceptional: input.copy(), exception: _typeError),
          )
        : invoked;
  }

  FlowState? _joinState(FlowState? a, FlowState? b) {
    if (a != null && b != null) return a.copy()..join(b);
    final incoming = a ?? b;
    if (incoming == null) return null;
    final result = incoming.copy();
    // A call accumulator starts with an unreachable outcome. Its only
    // executable predecessor retains the same partition of exceptional exits.
    if (_exceptionSources[incoming] case final alternatives?) {
      _exceptionSources[result] = {
        for (final entry in alternatives.entries) entry.key: entry.value.copy(),
      };
    }
    return result;
  }

  FlowResult _joinResult(FlowResult left, FlowResult right) {
    return FlowResult(
      value: left.value.join(right.value),
      normal: _joinState(left.normal, right.normal),
      normalRanges: left.normal == null
          ? right.normalRanges
          : right.normal == null
          ? left.normalRanges
          : left.normalRanges.isEmpty || right.normalRanges.isEmpty
          ? const {}
          : {
              for (final entry in left.normalRanges.entries)
                if (right.normalRanges[entry.key] case final other?)
                  entry.key: entry.value.join(other),
            },
      exceptional: _joinState(left.exceptional, right.exceptional),
      allocationFailureOnly:
          !left.hasSemanticFailure && !right.hasSemanticFailure,
      exception: left.exception.join(right.exception),
      stackTrace: left.stackTrace.join(right.stackTrace),
      effects: {...left.effects, ...right.effects},
    );
  }

  List<_Activation> _recursivePath(
    _Activation caller,
    Instruction operation,
    FunctionTarget target,
    List<FlowValue> arguments,
  ) {
    if (!_ancestry.mayHaveAncestor(caller.body.target, target)) return const [];
    bool matches(_Activation candidate) {
      if (candidate.body.target != target ||
          !candidate.callSites.any(
            (site) => identical(site.operation, operation),
          )) {
        return false;
      }
      // Distinct callbacks can re-enter the same helper without forming a cycle.
      for (final (index, argument) in arguments.indexed) {
        final incoming = _callableOrigins(argument);
        final existing = _callableOrigins(candidate.arguments[index]);
        if (incoming != null &&
            existing != null &&
            !incoming.any(existing.contains)) {
          return false;
        }
      }
      return true;
    }

    final child = <_Activation, _Activation?>{caller: null};
    final pending = [caller];
    for (var i = 0; i < pending.length; i++) {
      final item = pending[i];
      if (matches(item)) {
        final path = <_Activation>[];
        for (
          _Activation? current = item;
          current != null;
          current = child[current]
        ) {
          path.add(current);
        }
        return path.reversed.toList();
      }
      for (final parent in item.readers) {
        if (child.containsKey(parent) ||
            !_ancestry.mayHaveAncestor(parent.body.target, target)) continue;
        child[parent] = item;
        pending.add(parent);
      }
    }
    return const [];
  }

  void _indexInput(_Activation activation) {
    _ContextKey? key;
    if (_calls.contains(activation) &&
        !activation.recursive &&
        activation.shareInput) {
      final arguments = activation.arguments;
      final pairs = <(int, int)>[
        for (var i = 0; i < arguments.length; i++)
          for (var j = 0; j < i; j++)
            if (_equivalent(arguments[i], arguments[j])) (i, j),
      ];
      final state = activation.input!.copy()..retainSources((_) => false);
      key = _ContextKey(
        activation.body.target,
        arguments.map((value) => value.withSources(const [])).toList(),
        activation.environment,
        state.structuralKey,
        activation.repeated,
        pairs.fold<Object?>(null, (key, pair) => (key, pair)),
      );
    }
    if (key == activation.inputKey) return;
    if (activation.inputKey case final previous?) {
      final known = _inputs[previous]!;
      known.remove(activation);
      if (known.isEmpty) _inputs.remove(previous);
    }
    if (key != null) _inputs.putIfAbsent(key, () => {}).add(activation);
    activation.inputKey = key;
  }

  void _release(_Activation activation) {
    final pending = [activation];
    while (pending.isNotEmpty) {
      final old = pending.removeLast();
      if (!_calls.contains(old) ||
          _roots.containsValue(old) ||
          _escapedCalls.containsValue(old)) {
        continue;
      }
      if (old.readers.isNotEmpty) {
        _lostCaller = true;
      } else {
        _retire(old, pending);
      }
    }
  }

  // A cycle can retain its readers after the last invocation from a root was
  // redirected. Trace only between evaluations, after call sites are rebound.
  void _releaseDisconnected() {
    final reachable = {
      ..._roots.values,
      ..._escapedCalls.values,
    };
    final frontier = reachable.toList();
    for (var i = 0; i < frontier.length; i++) {
      for (final calls in frontier[i].calls.values) {
        for (final callee in calls) {
          if (reachable.add(callee)) frontier.add(callee);
        }
      }
    }
    for (final old in _calls.where((a) => !reachable.contains(a)).toList()) {
      _retire(old);
    }
  }

  void _retire(_Activation old, [List<_Activation>? children]) {
    // Published allocations still own their creator's capture, type argument,
    // and bound method facts through their original allocation identity.
    _calls.remove(old);
    _pending.remove(old);
    if (old.inputKey case final key?) {
      final bucket = _inputs[key]!;
      bucket.remove(old);
      if (bucket.isEmpty) _inputs.remove(key);
      old.inputKey = null;
    }
    // Native reentry also installs summary readers on callable roots.
    for (final root in [
      ..._escapingActivations,
      ..._roots.values,
    ]) {
      root.readers.remove(old);
    }
    for (final entry in old.calls.entries) {
      for (final called in entry.value) {
        final site = _callSites[(old, entry.key, called.body.target)];
        called.callSites.remove(site);
        called.readers.remove(old);
        children?.add(called);
      }
      for (final called in entry.value) {
        _callSites.remove((old, entry.key, called.body.target));
      }
    }
  }

  FlowStorageAccess? _accessFor(IrFunction body) {
    if (_storageAccess.containsKey(body.target)) {
      return _storageAccess[body.target];
    }
    // Local footprints start at the bottom, including recursive callees. Propagate
    // their finite dependencies to a fixed point instead of treating an SCC's
    // unfinished summary as unknown access to the caller's entire state.
    final discover = <FunctionTarget>[body.target];
    final callers = <FunctionTarget, Set<FunctionTarget>>{};
    for (var i = 0; i < discover.length; i++) {
      final target = discover[i];
      if (_storageAccess.containsKey(target)) continue;
      final local = _localStorageAccess(program.implementationOf(target));
      _storageAccess[target] = local.access;
      _allocating[target] = local.allocates;
      for (final callee in local.calls) {
        (callers[callee] ??= {}).add(target);
        discover.add(callee);
      }
    }
    final pending = discover.toSet();
    while (pending.isNotEmpty) {
      final callee = pending.first;
      pending.remove(callee);
      final incoming = _storageAccess[callee];
      for (final caller in callers[callee] ?? const <FunctionTarget>{}) {
        if (_allocating[callee] == true && _allocating[caller] != true) {
          _allocating[caller] = true;
          pending.add(caller);
        }
        final previous = _storageAccess[caller];
        if (previous == null) continue;
        if (incoming == null) {
          _storageAccess[caller] = null;
          pending.add(caller);
          continue;
        }
        final fields = previous.fields.length,
            globals = previous.globals.length,
            data = previous.data.length,
            modules = previous.modules.length;
        previous.fields.addAll(incoming.fields);
        previous.globals.addAll(incoming.globals);
        previous.data.addAll(incoming.data);
        previous.modules.addAll(incoming.modules);
        final next = (
          fields: previous.fields,
          globals: previous.globals,
          data: previous.data,
          modules: previous.modules,
          context: previous.context || incoming.context,
          cells: previous.cells || incoming.cells,
          memory: previous.memory || incoming.memory,
          writes: previous.writes || incoming.writes,
          exposed: previous.exposed || incoming.exposed,
          rawWrites: previous.rawWrites || incoming.rawWrites,
        );
        if (fields != next.fields.length ||
            globals != next.globals.length ||
            data != next.data.length ||
            modules != next.modules.length ||
            previous.context != next.context ||
            previous.cells != next.cells ||
            previous.memory != next.memory ||
            previous.writes != next.writes ||
            previous.exposed != next.exposed ||
            previous.rawWrites != next.rawWrites) {
          _storageAccess[caller] = next;
          pending.add(caller);
        }
      }
    }
    return _storageAccess[body.target];
  }

  bool _mayAllocate(IrFunction body) {
    _accessFor(body);
    return _allocating[body.target]!;
  }

  // One input plan owns both dispatch/branch dependencies and native write
  // ranges. It reads no mutable contents and consumes no previously solved
  // facts: changing caller input always obtains a fresh proof. Unknown values
  // retain every possible edge, including exceptional continuations.
  FlowStorageAccess? _accessForInput(
    IrFunction body,
    List<FlowValue> arguments,
    FlowState input,
  ) {
    final active = <FunctionTarget, (List<FlowValue>, FlowValue)>{};
    FlowStorageAccess? visit(
      FunctionTarget target,
      List<FlowValue>? arguments,
      FlowState state,
    ) {
      final body = program.implementationOf(target);
      final declared = body is IrFunction
          ? _accessFor(body)
          : _localStorageAccess(body).access;
      if (declared != null && !declared.rawWrites) return declared;
      if (arguments == null) return declared;
      if (body is IrExternal) {
        if (declared == null) return null;
        final memory = body.memory;
        if (memory is! WrittenMemory ||
            !state.boundsNativeRange(
              arguments[memory.addressParameter],
              arguments[memory.lengthParameter],
            )) {
          return declared;
        }
        return (
          fields: declared.fields,
          globals: declared.globals,
          data: declared.data,
          modules: declared.modules,
          context: declared.context,
          cells: declared.cells,
          memory: declared.memory,
          writes: declared.writes,
          exposed: declared.exposed,
          rawWrites: false,
        );
      }
      if (body is! IrFunction || body.bodyKind != .synchronous) return declared;
      final plain = arguments
          .map((value) => value.withSources(const []))
          .toList();
      final context = state.nativeContext.withSources(const []);
      if (active[target] case final previous?) {
        // A repeated identical proof closes its dependency cycle. Changing
        // recursive arguments instead retain the declaration's conservative
        // fixed point; recursion never creates an unbounded proof worklist.
        return _sameValues(previous.$1, plain) && previous.$2 == context
            ? _emptyStorageAccess()
            : declared;
      }
      active[target] = (plain, context);
      try {
        final plan = _accessPlans.putIfAbsent(target, () => _AccessPlan(body));
        final proofState = plan.bindsContext
            ? state.copy(nativeContext: FlowValue.unknown(.integer))
            : state;
        final values = <Value, FlowValue>{
          for (final (index, parameter) in body.entry.parameters.indexed)
            parameter: plain[index],
        };
        FlowValue read(Value value) {
          if (value is Constant) return FlowValue.constant(value);
          if (values[value] case final known?) return known;
          // A cyclic phi starts unknown, not bottom. Every incoming edge is
          // included, even if its predecessor is not currently selected.
          values[value] = FlowValue.unknown(value.type);
          FlowValue? result;
          if (value is BlockParameter) {
            final block = plan.parameters[value]!;
            final index = block.parameters.indexOf(value);
            result = FlowValue.joined([
              for (final edge in plan.incoming[block] ?? const <Jump>[])
                read(edge.arguments[index]),
            ]);
          } else if (value is Instruction) {
            final operands = value.inputs.map(read).toList();
            final folded = _fold(value, operands, program);
            if (folded != null) {
              result = FlowValue.constant(folded);
            } else {
              switch (value) {
                case LoadField()
                    when operands.single.objects.isEmpty &&
                        operands.single.unknownTypes.isEmpty &&
                        operands.single.addresses.isEmpty:
                  // Constants and their type-layout views are immutable. No
                  // caller slot or previously solved mutable fact is read.
                  result = proofState.boundValueOf(value, operands);
                case ReferenceAddress():
                  result = _referenceAddress(operands.single);
                case TypeView() ||
                    UncheckedCast() ||
                    PointerAddress() ||
                    PointerFromAddress():
                  result = operands.single;
                case IntBinary():
                  result =
                      (value.operator == .add || value.operator == .subtract) &&
                          operands.any(
                            (operand) => operand.addresses.isNotEmpty,
                          )
                      ? _addressArithmetic(value, operands)
                      : _integerOperation(value, operands)?.value;
                case ReadNativeContext() ||
                    NativeDataAddress() ||
                    ModuleObjectReference() ||
                    NativeSize() ||
                    NativeFieldOffset():
                  result = proofState
                      .transfer(
                        value,
                        operands,
                        allocate: (_) => throw StateError(
                          'An access proof cannot allocate.',
                        ),
                        repeated: false,
                        invoke: (_, _, _) =>
                            throw StateError('An access proof cannot invoke.'),
                        call: (_, _, _) =>
                            throw StateError('An access proof cannot call.'),
                      )!
                      .value;
                default:
                  break;
              }
            }
          }
          return values[value] = result ?? FlowValue.unknown(value.type);
        }

        final reached = <Block>{};
        final pending = [body.entry];
        final operations = <Instruction>[];
        while (pending.isNotEmpty) {
          final block = pending.removeLast();
          if (!reached.add(block)) continue;
          operations.addAll(block.instructions);
          if (block.end case Invoke(:final operation)) {
            operations.add(operation);
          }
          var edges = block.successors;
          if (block.end case Branch(
            :final condition,
            :final ifTrue,
            :final ifFalse,
          )) {
            if (read(condition).constant case ScalarConstant(
              value: bool value,
            )) {
              edges = [value ? ifTrue : ifFalse];
            }
          }
          pending.addAll(edges.map((edge) => edge.target));
        }
        return _localStorageAccess(
          body,
          operations: operations,
          read: read,
          invoke: (callee, arguments) => visit(callee, arguments, proofState),
          boundedWrite: (operation) => proofState.boundsNativeWrite(
            operation,
            operation.inputs.map(read).toList(),
          ),
        ).access;
      } finally {
        active.remove(target);
      }
    }

    return visit(body.target, arguments, input);
  }

  ({FlowStorageAccess? access, Set<FunctionTarget> calls, bool allocates})
  _localStorageAccess(
    IrCallable? body, {
    Iterable<Instruction>? operations,
    FlowValue Function(Value)? read,
    FlowStorageAccess? Function(FunctionTarget, List<FlowValue>?)? invoke,
    bool Function(Instruction)? boundedWrite,
  }) {
    final fields = <InstanceField>{}, globals = <GlobalVariable>{};
    final data = <NativeData>{};
    final modules = <ModuleObject>{};
    final calls = <FunctionTarget>{};
    var cells = false, memory = false, writes = false, exposed = false;
    var context = false, rawWrites = false, opaque = false;
    var allocates = false;
    FlowStorageAccess getAccess() => (
      fields: fields,
      globals: globals,
      data: data,
      modules: modules,
      context: context,
      cells: cells,
      memory: memory,
      writes: writes,
      exposed: exposed,
      rawWrites: rawWrites,
    );
    void addCall(FunctionTarget target, List<FlowValue>? arguments) {
      calls.add(target.implementation);
      if (invoke == null) return;
      final incoming = invoke(target.implementation, arguments);
      if (incoming == null) {
        opaque = true;
        return;
      }
      fields.addAll(incoming.fields);
      globals.addAll(incoming.globals);
      data.addAll(incoming.data);
      modules.addAll(incoming.modules);
      context |= incoming.context;
      cells |= incoming.cells;
      memory |= incoming.memory;
      writes |= incoming.writes;
      exposed |= incoming.exposed;
      rawWrites |= incoming.rawWrites;
    }

    if (body is IrExternal) {
      if (body.effects.contains(Effect.callsUserCode)) {
        return (access: null, calls: calls, allocates: true);
      }
      // Storage-reading or writing leaves may use capabilities escaped by an
      // earlier call. A closed, non-capturing leaf with no storage effects has
      // no such demand; its mere presence does not expose the caller's heap.
      memory = exposed = body.capturesArguments ||
          body.effects.contains(Effect.readsStorage) ||
          body.effects.contains(Effect.writesStorage);
      writes =
          body.capturesArguments ||
          body.effects.contains(Effect.writesStorage) &&
              body.memory is! UnchangedMemory &&
              body.memory is! ZeroedMemory;
      rawWrites = body.memory is WrittenMemory || body.memory is ReleasedMemory ||
          body.memory is NativeResultMemory;
      return (access: getAccess(), calls: calls,
          allocates: body.effects.contains(Effect.allocates));
    }
    if (body is! IrFunction || body.bodyKind != .synchronous) {
      return (access: null, calls: calls, allocates: true);
    }
    FlowValue valueOf(Value value) =>
        read?.call(value) ?? FlowValue.unknown(value.type);
    bool virtualTargets(
      FlowValue receiver,
      MemberSelector selector,
      List<FlowValue> positional,
      Map<String, FlowValue> named, {
      MemberEntryBinding? binding,
      List<FlowValue> executionTypes = const [],
    }) {
      var found = false;
      for (final type in _receiverTypes(receiver)) {
        final lookup = program.lookupMember(type, selector);
        final target = lookup.target;
        if (target == null ||
            lookup.unmodeledBoundary != null ||
            lookup.unsupportedForwarder ||
            !target.signature.acceptsShape(positional.length, named.keys)) {
          return false;
        }
        final callee = program.implementationOf(target);
        if (callee == null) return false;
        if (binding != null) {
          final entry = binding.entries[target];
          if (entry == null || program.implementationOf(entry) == null) {
            return false;
          }
          addCall(entry, read == null ? null : [
            _receiverValue(receiver, type),
            ...positional,
            for (final name in binding.names) named[name]!,
            ...executionTypes,
          ]);
          if (opaque) return false;
          found = true;
          continue;
        }
        addCall(
          target,
          read == null
              ? null
              : [
                  _receiverValue(receiver, type),
                  ...target.signature.bind<FlowValue>(
                    positional,
                    named,
                    (index) => FlowValue.constant(callee.defaults[index]!),
                  ),
                ],
        );
        if (opaque) return false;
        found = true;
      }
      return found;
    }

    for (final operation
        in operations ??
            [
              for (final block in body.blocks) ...[
                ...block.instructions,
                if (block.end case Invoke(:final operation)) operation,
              ],
            ]) {
      if (opaque) return (access: null, calls: calls, allocates: true);
      final inputs = operation.inputs.map(valueOf).toList();
      // The real transfer folds before assigning effects. Reuse the same proof
      // rather than suppressing a call based on its earlier solved effects.
      if (read != null && _fold(operation, inputs, program) != null) continue;
      switch (operation) {
        case ReadNativeContext():
          context = memory = true;
        case BindNativeContext():
          continue;
        case ReferenceAddress():
          // Observing identity retains the input capability, but does not read
          // its fields or bytes. Later raw reads contribute their own demand.
          continue;
        case NativeDataAddress(:final declaration):
          data.add(declaration);
          memory = true;
        case ModuleObjectReference(:final declaration):
          modules.add(declaration);
          continue;
        case ModuleRootsAddress():
          modules.addAll(
            program.functions.expand((body) => body.moduleObjects),
          );
          memory = true;
        case ManagedStorageAllocation(allocator: final target) ||
            DirectCall(:final target) ||
            CheckedTypeArgument(implementation: final target?):
          addCall(target, inputs);
          continue;
        case InitializeObject(:final initializer):
          addCall(initializer, inputs);
          continue;
        case Construct(
          :final initializer,
          :final instantiatedType,
          :final callableStorage,
        ):
          addCall(initializer, [
            FlowValue.unknown(instantiatedType),
            ...callableStorage == null
                ? inputs
                : inputs.take(inputs.length - 1),
          ]);
        case InstanceCall(
          :final receiver,
          :final member,
          :final positional,
          :final named,
          :final entryBinding,
          :final executionTypes,
        ):
          if (!virtualTargets(
            valueOf(receiver),
            member.selector,
            positional.map(valueOf).toList(),
            {
              for (final entry in named.entries)
                entry.key: valueOf(entry.value),
            },
            binding: entryBinding,
            executionTypes: executionTypes.map(valueOf).toList(),
          )) {
            return (access: null, calls: calls, allocates: true);
          }
          continue;
        case FunctionCall(entryBinding: final binding?):
          // The storage footprint can use registered entries, but this local
          // proof has not established that all dynamic origins are covered.
          allocates = true;
          for (final target in binding.entries.values) {
            addCall(target, null);
          }
          memory = true;
          continue;
        case BindMethod(entryBinding: != null):
          // The actual producer can read or write state before returning its
          // closure. Until its complete target footprint is proven here, keep
          // all incoming storage rather than using the source tear-off shape.
          return (access: null, calls: calls, allocates: true);
        case FunctionCall(target: final target?):
          allocates = true;
          // Hidden capture values remain unknown to this input-only proof.
          addCall(target, null);
          memory = true;
          continue;
        case LoadGlobal(:final global):
          globals.add(global);
          if (global.initializer case final initializer?) {
            addCall(initializer, const []);
            writes = true;
          }
          continue;
        case StoreGlobal(:final global):
          globals.add(global);
          writes = true;
        case LoadField(:final field):
          fields.add(field);
          if (field.initializer case final initializer?) {
            addCall(initializer, inputs);
            writes = true;
          }
          continue;
        case StoreField(:final field) || InitializeStorageField(:final field):
          fields.add(field);
          writes = true;
        case ReadCell(cell: Value(type: CellType(isLate: true))):
          return (access: null, calls: calls, allocates: true);
        case ReadCell() || CopyCell():
          cells = true;
        case ObjectRuntimeType(direct: true) || TypeTest() || TypeCast():
          memory |= inputs.any((value) =>
              value.objects.any((object) => object.callableStorage != null) ||
              value.unknownTypes.any((type) => type is FunctionType ||
                  type.accepts(ValueType.function)));
        case ReadFunctionEnvironment() || ReadFunctionTypeArgument():
          memory = true;
        case WriteCell():
          cells = writes = true;
        case LoadNative() ||
            LoadObjectData() ||
            LoadObjectReference() ||
            StringLength() ||
            StringCodeUnitAt() ||
            ReferenceFromAddress() ||
            AllocatedObject() ||
            InstantiateFunction() ||
            InstantiateFunctionFrom():
          memory = true;
        case StoreNative() ||
            StoreObjectData() ||
            StoreObjectReference() ||
            CopyNative():
          memory = writes = true;
          rawWrites |= boundedWrite == null || !boundedWrite(operation);
        default:
          if (operation.implicitMember case final member?) {
            if (!virtualTargets(
              read == null ? FlowValue.unknown(member.receiver) : inputs.first,
              member.selector,
              inputs.skip(1).toList(),
              const {},
            )) {
              return (access: null, calls: calls, allocates: true);
            }
            continue;
          }
          if (operation.effects.contains(Effect.callsUserCode)) {
            return (access: null, calls: calls, allocates: true);
          }
          memory |=
              operation.effects.contains(Effect.readsStorage) ||
              operation.effects.contains(Effect.writesStorage);
          writes |= operation.effects.contains(Effect.writesStorage);
      }
      allocates |= operation.effects.contains(Effect.allocates);
      if (allocationFailure case final failure?
          when operation.effects.contains(Effect.allocates)) {
        addCall(failure, const []);
      }
    }
    return (access: opaque ? null : getAccess(), calls: calls,
        allocates: opaque || allocates);
  }

  void _evaluate(_Activation activation) {
    final body = activation.body;
    if (activation.input == null) return;
    _definitions.add(body.target);
    if (body is! IrFunction) return;
    if (body.bodyKind != .synchronous) {
      throw StateError(
        'Normalize suspension before program flow: '
        '${body.target.library}::${body.target.name}.',
      );
    }
    // Recursive supply may grow activation.input while this body is evaluated.
    // Each published exit remains paired with the entry actually analyzed.
    final entryState = activation.input!.copy();
    // Local snapshots belong to this evaluation; only call summaries propagate.
    activation.before.clear();
    activation.after.clear();
    activation.thrown.clear();
    activation.edgeStates.clear();
    activation.environmentReads.clear();
    activation.storageViews.clear();
    final escapes =
        !_nativeLookups.contains(activation) &&
        (_escapingActivations.contains(activation) ||
            (_escapingReturns.contains(body.target) &&
                identical(_roots[body.target], activation)));
    bool availableAt(FlowSource source, Block block) =>
        !identical(source.activation, activation) ||
        !block.parameters.contains(source.value) &&
            activation.dominance.atEntry(source.value, block);
    final incoming = <Block, FlowState>{
      body.entry: entryState.copy()
        ..retainSources((source) => availableAt(source, body.entry)),
    };
    final incomingRanges = <Block, Map<Value, FlowIntegerRange>>{
      body.entry: {},
    };
    final pending = <Block>{body.entry};
    final readers = <Value, Set<Block>>{};
    final loops = _loops.putIfAbsent(body.target, () => LoopRanges(body));
    final loopProofs = <LoopRange, LoopRangeProof>{};
    final evaluated = <Value>{};
    FlowIntegerRange? loopRange(Value value, Block block) {
      FlowIntegerRange? result;
      for (final proof in loopProofs.values) {
        final range = proof.range(value, block);
        if (range != null) {
          result = result == null ? range : result.intersect(range);
        }
      }
      return result;
    }

    void proveLoop(LoopRange loop) {
      final proof = loop.prove(
        (value) => value is Constant
            ? FlowValue.constant(value).integers
            : evaluated.contains(value) &&
                (activation.values[value]?.managedBackings.isEmpty ?? false) &&
                !(activation.values[value]?.hasUnknownBacking ?? false)
            ? activation.values[value]?.integers
            : null,
        (operation) {
          final calls = activation.calls[operation];
          final effects = {
            ...?activation.operationEffects[operation],
            ...?activation.externalEffects[operation],
            if (calls != null)
              for (final call in calls) ...call.effects
            else if (!activation.operationEffects.containsKey(operation))
              ...operation.effects,
          };
          return effects.every((effect) => effect == .mayThrow);
        },
      );
      if (proof == null) {
        loopProofs.remove(loop);
      } else {
        loopProofs[loop] = proof;
      }
    }

    late Block readingBlock;
    late Map<Value, FlowIntegerRange> ranges;
    late FlowState point;
    bool mergeValue(Value value, FlowValue incoming, {bool widen = false}) {
      evaluated.add(value);
      if (!activation.mergeValue(
        value,
        incoming,
        widen: widen,
        bound: incoming.managedBackings.isEmpty && !incoming.hasUnknownBacking
            ? loopRange(value, loops.owners[value] ?? body.entry) : null,
      )) {
        return false;
      }
      pending.addAll(readers[value] ?? const []);
      return true;
    }

    for (final (index, parameter) in body.entry.parameters.indexed) {
      mergeValue(
        parameter,
        activation.arguments[index].withSource(parameter, activation),
      );
    }
    var summaryChanged = false;

    FlowValue constrained(FlowValue value) {
      if (value.managedBackings.isNotEmpty || value.hasUnknownBacking) return value;
      for (final source in value.sources) {
        if (!identical(source.activation, activation)) continue;
        if (ranges[source.value] case final range?) {
          value = value.restrictIntegers(range);
        }
        if (loopRange(source.value, readingBlock) case final range?) {
          value = value.restrictIntegers(range);
        }
      }
      return value;
    }

    FlowValue read(Value value) {
      switch (value) {
        case Constant():
          return FlowValue.constant(value);
        case TestedValue(:final test, :final outcome):
          return read(test.operand)
              .check(
                test.testedType.substituteForFlow(
                  activation.executionEnvironment,
                ),
                negated: outcome == test.negated,
                runtimeTypes: true,
              )
              .value;
        case UnwindValue() || CallFrameValue():
          return FlowValue.unknown(value.type);
        default:
          (readers[value] ??= {}).add(readingBlock);
          final known = constrained(
            point.resolveValue(
              activation.values[value] ?? const FlowValue.bottom(),
            ),
          );
          if (known.managedBackings.isNotEmpty || known.hasUnknownBacking) {
            // A carrier can be changed through an actual raw capability. Whole
            // SSA replacement facts must cover every observed payload, while
            // this use consumes the current storage and no stale numeric range.
            mergeValue(value, known);
            return known;
          }
          final bounded = switch (loopRange(value, readingBlock)) {
            final range? => known.restrictIntegers(range),
            null => known,
          };
          return switch (ranges[value]) {
            final range? => bounded.restrictIntegers(range),
            null => bounded,
          };
      }
    }

    // A loop backedge can retire the previously selected mapping and supply
    // zero as its successor. A pure guard may consume each predecessor's
    // binding before its storage is joined with unrelated alternatives.
    final guardStates = <(Block, bool), FlowState>{};
    final parameterGuards =
        <Block, ({int parameter, int? constant, bool negated})>{};
    for (final loop in loops.loops) {
      final header = loop.header;
      if (header.instructions.length != 1 || header.end is! Branch) {
        continue;
      }
      final branch = header.end as Branch;
      final test = branch.condition;
      if (test
          case TypeTest(
            operand: final BlockParameter input,
            testedType: ValueType.nullType,
            :final negated,
          )
          when identical(header.instructions.single, test)) {
        final index = header.parameters.indexOf(input);
        if (index >= 0) {
          parameterGuards[header] = (
            parameter: index,
            constant: null,
            negated: negated,
          );
        }
        continue;
      }
      if (test is! Equals ||
          !identical(header.instructions.single, test) ||
          test.mayCallUserCode) {
        continue;
      }
      for (final (parameter, constant) in [
        (test.left, test.right),
        (test.right, test.left),
      ]) {
        if (constant case ScalarConstant(value: final int n)
            when parameter is BlockParameter && parameter.type == ValueType.integer) {
          final index = header.parameters.indexOf(parameter);
          if (index >= 0) {
            parameterGuards[header] = (parameter: index, constant: n, negated: test.negated);
          }
        }
      }
    }

    void edge(
      Jump jump,
      FlowState state, {
      FlowValue? exception,
      FlowValue? stackTrace,
      Map<Value, FlowIntegerRange>? refinements,
    }) {
      // Re-entry can change a nested loop's starting values and invariant bound.
      loopProofs.removeWhere(
        (loop, _) => loop.header == jump.target && !loop.backs.contains(jump),
      );
      point = state;
      final nextRanges = {...ranges, ...?refinements};
      for (final entry
          in refinements?.entries ??
              const <MapEntry<Value, FlowIntegerRange>>[]) {
        for (final source in read(entry.key).sources) {
          if (!identical(source.activation, activation)) continue;
          final previous = nextRanges[source.value];
          final range = previous == null
              ? entry.value
              : previous.intersect(entry.value);
          if (range == null) return;
          nextRanges[source.value] = range;
        }
      }
      final widen = activation.backEdges.contains(jump);
      for (final operation in [
        ...jump.target.instructions,
        if (jump.target.end case Invoke(:final operation)) operation,
      ]) {
        nextRanges.remove(operation);
      }
      activation.edges.add(jump);
      if (activation.edgeStates[jump] case final known?) {
        known.join(state);
      } else {
        activation.edgeStates[jump] = state.copy();
      }
      // Stored aliases refer to the previous binding when a loop re-enters.
      final nextState = state.copy()
        ..retainSources((source) => availableAt(source, jump.target));
      if (_exceptionSources[state] case final alternatives?) {
        _exceptionSources[nextState] = {
          for (final entry in alternatives.entries)
            entry.key: (entry.value.copy()..retainSources((source) => availableAt(source, jump.target))),
        };
      }
      var changed = false;
      final guard = parameterGuards[jump.target];
      bool? guardValue;
      for (final (index, parameter) in jump.target.parameters.indexed) {
        var value = switch (jump.arguments[index]) {
          UnwindValue.exception => exception ?? FlowValue.unknown(.object),
          UnwindValue.stackTrace =>
            stackTrace ?? FlowValue.unknown(.stackTrace),
          final argument => read(argument),
        };
        if (nextRanges[jump.arguments[index]] case final range?) {
          value = value.restrictIntegers(range);
        }
        value = value.withSources(
          value.sources.where((source) => availableAt(source, jump.target)),
        );
        nextRanges.remove(parameter);
        if (value.integers case final range?
            when range != FlowIntegerRange.full) {
          nextRanges[parameter] = range;
        }
        if (guard != null &&
            guard.parameter == index &&
            value.managedBackings.isEmpty &&
            !value.hasUnknownBacking) {
          if (guard.constant case final expected?) {
            if (value.constant case ScalarConstant(value: final int actual)) {
              guardValue = (actual == expected) != guard.negated;
            } else if (value.integers case final range?
                when !range.contains(expected)) {
              guardValue = guard.negated;
            }
          } else {
            final checked = value.check(ValueType.nullType, runtimeTypes: true);
            if (!checked.mayFail) {
              guardValue = !guard.negated;
            } else if (checked.value.isBottom) {
              guardValue = guard.negated;
            }
          }
        }
        changed =
            mergeValue(
              parameter,
              value.withSource(parameter, activation),
              widen: widen,
            ) ||
            changed;
      }
      nextState.refineIntegers({
        for (final entry in nextRanges.entries)
          FlowSource(entry.key, activation): entry.value,
      });
      if (guard != null) {
        for (final outcome in const [true, false]) {
          if (guardValue != null && outcome != guardValue) continue;
          final key = (jump.target, outcome);
          final previous = guardStates[key];
          if (previous == null) {
            guardStates[key] = nextState.copy();
            changed = true;
          } else {
            changed = previous.join(nextState, widen: widen) || changed;
          }
        }
      }
      if (incomingRanges[jump.target] case final previous?) {
        changed = _joinRanges(previous, nextRanges, widen: widen) || changed;
      } else {
        incomingRanges[jump.target] = nextRanges;
        changed = true;
      }
      if (incoming[jump.target] case final previous?) {
        final before = _exceptionSources[previous];
        final additional = _exceptionSources[nextState];
        if (before != null) {
          if (additional == null || additional.keys.any((key) => !before.containsKey(key))) {
            _exceptionSources[previous] = null;
            changed = true;
          } else {
            for (final entry in additional.entries) {
              changed = before[entry.key]!.join(entry.value, widen: widen) || changed;
            }
          }
        }
        changed = previous.join(nextState, widen: widen) || changed;
      } else {
        incoming[jump.target] = nextState;
        changed = true;
      }
      if (changed) pending.add(jump.target);
    }

    void exceptional(
      Object source,
      FlowState state,
      FlowValue exception,
      FlowValue stackTrace, {
      bool allocationFailureOnly = false,
    }) {
      final alternatives = _exceptionSources[state];
      state = state.copy(nativeContext: entryState.nativeContext);
      if (!allocationFailureOnly && !activation.hasSemanticFailure) {
        activation.hasSemanticFailure = true;
        summaryChanged = true;
      }
      if (escapes && !_nativeActivations.contains(activation)) {
        state.escape([exception, stackTrace]);
        _admitEscaped(state);
      }
      final previous = activation.exceptionalSummary;
      var lanes = activation.exceptionSources;
      if (lanes == null &&
          (alternatives != null ||
              previous != null &&
                  activation.firstExceptionSite != source &&
                  previous.exit.losesNativeExtent(state))) {
        lanes = activation.exceptionSources = {};
        if (previous != null) {
          final covered =
              alternatives != null &&
              alternatives.values.any((alternative) {
                final upper = alternative.copy(
                  nativeContext: entryState.nativeContext,
                );
                if (escapes && !_nativeActivations.contains(activation)) {
                  upper.escape([exception, stackTrace]);
                }
                return !upper.join(previous.exit);
              });
          if (!covered) {
            lanes[activation.firstExceptionSite!] = _StateSummary(
              previous.entry,
              previous.exit,
            );
          }
        }
        summaryChanged = true;
      }
      if (lanes != null) {
        final incoming = alternatives ?? {source: state};
        for (final pair in incoming.entries) {
          final snapshot = alternatives == null
              ? pair.value
              : pair.value.copy(nativeContext: entryState.nativeContext);
          if (alternatives != null &&
              escapes &&
              !_nativeActivations.contains(activation)) {
            snapshot.escape([exception, stackTrace]);
          }
          final lane = lanes[pair.key];
          if (lane != null) {
            summaryChanged |= lane.join(
              entryState,
              snapshot,
              widen: activation.recursive,
            );
          } else {
            // Several throw sites can leave the same mappings live. Join
            // their ordinary state but keep incompatible extents separate,
            // so cleanup can still select a live mapping.
            final compatible = lanes.values.where(
              (lane) => !lane.exit.losesNativeExtent(snapshot),
            );
            if (compatible.any(
              (lane) =>
                  !lane.entry.copy().join(entryState) &&
                  !lane.exit.copy().join(snapshot),
            )) {
              continue;
            }
            final shared = compatible.firstOrNull;
            if (shared == null) {
              lanes[pair.key] = _StateSummary(entryState, snapshot);
              summaryChanged = true;
            } else {
              summaryChanged |= shared.join(
                entryState,
                snapshot,
                widen: activation.recursive,
              );
            }
          }
        }
      } else {
        final first = activation.firstExceptionSite;
        activation.firstExceptionSite = first == null || first == source
            ? source
            : activation;
      }
      final joinedException = activation.exception.join(exception);
      final joinedTrace = activation.stackTrace.join(stackTrace);
      summaryChanged |=
          joinedException != activation.exception ||
          joinedTrace != activation.stackTrace;
      activation.exception = joinedException;
      activation.stackTrace = joinedTrace;
      if (activation.exceptionalSummary == null) {
        activation.exceptionalSummary = _StateSummary(entryState, state);
        summaryChanged = true;
      } else {
        summaryChanged =
            activation.exceptionalSummary!.join(
              entryState,
              state,
              widen: activation.recursive,
            ) ||
            summaryChanged;
      }
    }

    while (pending.isNotEmpty) {
      final block = pending.first;
      pending.remove(block);
      readingBlock = block;
      ranges = {...incomingRanges[block]!};
      activation.blocks.add(block);
      final current = incoming[block]!;
      FlowState? state = current.copy();
      if (_exceptionSources[current] case final alternatives?) {
        _exceptionSources[state] = alternatives;
      }
      FlowResult evaluate(Instruction operation) {
        point = state!;
        activation.before[operation] = state.copy();
        if (body.typeBindings.isNotEmpty) {
          body.typeInputsOf(operation).forEach(read);
        }
        var result = _operation(
          activation,
          block,
          operation,
          operation.inputs.map(read).toList(),
          state,
          read,
        );
        if (activation.operationEffects[operation]?.contains(
              Effect.allocates,
            ) ??
            false) {
          final target = allocationFailure;
          final failed = target == null
              ? FlowResult(
                  exceptional: state.copy(),
                  exception: FlowValue.unknown(ValueType.error),
                )
              : _invoke(
                  activation,
                  block,
                  activation.allocationCalls.putIfAbsent(
                    operation,
                    () => DirectCall(target, []),
                  ),
                  target,
                  const [],
                  state,
                );
          result = _joinResult(
            result,
            FlowResult(
              exceptional: failed.exceptional,
              exception: failed.exception,
              stackTrace: failed.stackTrace,
              allocationFailureOnly: true,
            ),
          );
        }
        final type = operation.type.substituteForFlow(
          activation.executionEnvironment,
        );
        var bounded = result.value;
        if (bounded.types.any((actual) => !type.accepts(actual))) {
          // Caller bounds also constrain unresolved receiver type arguments.
          bounded = bounded.check(type).value;
        }
        bounded = constrained(bounded);
        if ((program.executionShapes ?? ExecutionShapes.defaults)
                .shapeOf(body, operation).isReference &&
            ExecutionShapes.forType(type).isScalar &&
            bounded.unknownTypes.isNotEmpty && bounded.managedBackings.isEmpty) {
          bounded = bounded.withManagedBackings(const [], unknown: true);
        }
        if (bounded != result.value) {
          result = FlowResult(
            value: bounded,
            normal: bounded.isBottom ? null : result.normal,
            normalRanges: result.normalRanges,
            exceptional: result.exceptional,
            allocationFailureOnly: result.allocationFailureOnly,
            exception: result.exception,
            stackTrace: result.stackTrace,
            effects: result.effects,
          );
        }
        mergeValue(operation, result.value.withSource(operation, activation));
        ranges.remove(operation);
        if (result.value.integers case final range?
            when range != FlowIntegerRange.full &&
                result.value.managedBackings.isEmpty &&
                !result.value.hasUnknownBacking) {
          ranges[operation] = range;
        }
        if (result.normal != null) {
          activation.after[operation] = result.normal!.copy();
        }
        if (result.hasSemanticFailure) {
          activation.semanticFailures.add(operation);
        }
        if (result.exceptional != null) {
          activation.exceptions[operation] =
              (activation.exceptions[operation] ?? const FlowValue.bottom())
                  .join(result.exception);
          activation.traces[operation] =
              (activation.traces[operation] ?? const FlowValue.bottom()).join(
                result.stackTrace,
              );
          activation.thrown[operation] = result.exceptional!.copy();
        }
        final exits =
            activation.exits[operation] ?? (normal: false, exceptional: false);
        activation.exits[operation] = (
          normal: exits.normal || result.normal != null,
          exceptional: exits.exceptional || result.exceptional != null,
        );
        return result;
      }

      for (final operation in block.instructions) {
        final result = evaluate(operation);
        if (result.exceptional case final thrown?) {
          exceptional(
            operation,
            thrown,
            result.exception,
            result.stackTrace,
            allocationFailureOnly: result.allocationFailureOnly,
          );
        }
        state = result.normal;
        if (state == null) break;
        if (result.normalRanges.isNotEmpty) {
          ranges.addAll(result.normalRanges);
          state.refineIntegers({
            for (final entry in result.normalRanges.entries)
              FlowSource(entry.key, activation): entry.value,
          });
        }
      }
      if (state == null) continue;
      point = state;
      switch (block.end) {
        case Return(:final value):
          final returned = value == null ? _null : read(value);
          state = state.copy(nativeContext: entryState.nativeContext);
          if (escapes) {
            state.escape([returned, ?_constructedReturns[activation]]);
            _admitEscaped(state);
          }
          final joined = activation.returned.join(
            returned,
            widen: activation.recursive,
          );
          summaryChanged |= joined != activation.returned;
          activation.returned = joined;
          final parameterRanges = <int, FlowIntegerRange>{
            for (final (i, parameter) in body.entry.parameters.indexed)
              if (ranges[parameter] case final range?
                  when range != FlowIntegerRange.full &&
                      activation.arguments[i].managedBackings.isEmpty &&
                      !activation.arguments[i].hasUnknownBacking)
                i: range,
          };
          if (activation.normalSummary == null) {
            activation.normalParameterRanges.addAll(parameterRanges);
            activation.normalSummary = _StateSummary(entryState, state);
            summaryChanged = true;
          } else {
            summaryChanged =
                _joinRanges(
                  activation.normalParameterRanges,
                  parameterRanges,
                  widen: activation.recursive,
                ) ||
                summaryChanged;
            summaryChanged =
                activation.normalSummary!.join(
                  entryState,
                  state,
                  widen: activation.recursive,
                ) ||
                summaryChanged;
          }
        case final Jump jump:
          edge(jump, state);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          for (final loop in loops.loops) {
            if (loop.blocks.contains(block) && loop.guards(block)) {
              proveLoop(loop);
            }
          }
          final value = read(condition);
          if (value.isBottom) break;
          if (value.constant case ScalarConstant(value: final bool known)) {
            final selected = known ? ifTrue : ifFalse;
            edge(selected, guardStates[(block, known)] ?? state);
          } else {
            var predicate = condition;
            if (condition is BlockParameter &&
                block != body.entry &&
                block.instructions.isEmpty &&
                value.managedBackings.isEmpty &&
                !value.hasUnknownBacking) {
              final index = block.parameters.indexOf(condition);
              if (loops.incoming[block] case [(final producer, final jump)]
                  when index >= 0 && identical(producer.end, jump)) {
                // Only the comparison just executed on this edge can constrain
                // its operands here. A saved boolean may refer to an earlier turn.
                final comparison = jump.arguments[index];
                if (comparison is IntBinary &&
                    identical(producer.instructions.lastOrNull, comparison) &&
                    comparison.inputs.map(read).every(
                      (operand) =>
                          operand.managedBackings.isEmpty &&
                          !operand.hasUnknownBacking,
                    )) {
                  predicate = comparison;
                }
              }
            }
            final yes = _integerRefinements(predicate, true, read);
            final no = _integerRefinements(predicate, false, read);
            FlowState branch(bool outcome) {
              final selected = guardStates[(block, outcome)] ?? state!;
              if (condition is! TypeTest) return selected;
              return selected.copy()..refineType(
                read(condition.operand).sources,
                condition.testedType.substituteForFlow(
                  activation.executionEnvironment,
                ),
                negated: outcome == condition.negated,
              );
            }

            final guarded = parameterGuards.containsKey(block);
            if (yes != null &&
                (!guarded || guardStates.containsKey((block, true)))) {
              edge(ifTrue, branch(true), refinements: yes);
            }
            if (no != null &&
                (!guarded || guardStates.containsKey((block, false)))) {
              edge(ifFalse, branch(false), refinements: no);
            }
          }
        case Invoke(:final operation, :final onReturn, :final onThrow):
          final result = evaluate(operation);
          if (onReturn != null && result.normal != null) {
            edge(onReturn, result.normal!, refinements: result.normalRanges);
          }
          if (result.exceptional case final thrown?) {
            edge(
              onThrow,
              thrown,
              exception: result.exception,
              stackTrace: result.stackTrace,
            );
          }
        case Throw(:final exception, :final stackTrace, :final onThrow):
          final value = read(exception);
          final trace = stackTrace == null
              ? FlowValue.unknown(.stackTrace)
              : read(stackTrace);
          if (onThrow == null) {
            exceptional(block.end, state, value, trace);
          } else {
            edge(onThrow, state, exception: value, stackTrace: trace);
          }
        case ExhaustivenessFailure(:final onThrow):
          if (onThrow == null) {
            exceptional(
              block.end,
              state,
              FlowValue.unknown(.object),
              FlowValue.unknown(.stackTrace),
            );
          } else {
            edge(onThrow, state);
          }
        case Unreachable():
          break;
        case Await() || Yield() || YieldStream():
          throw StateError('Suspension reached an ordinary execution graph.');
      }
    }
    final beforeEffects = activation.effects.length;
    for (final effects in [
      ...activation.operationEffects.values,
      ...activation.externalEffects.values,
    ]) {
      activation.effects.addAll(effects.where((effect) => effect != .mayThrow));
    }
    for (final callees in activation.calls.values) {
      for (final callee in callees) {
        activation.effects.addAll(
          callee.effects.where((effect) => effect != .mayThrow),
        );
      }
    }
    if (activation.hasSemanticFailure) activation.effects.add(Effect.mayThrow);
    if (body.target == allocationFailure?.implementation &&
        activation.effects.contains(Effect.allocates)) {
      throw StateError('Allocation failure reporting cannot allocate.');
    }
    summaryChanged |= beforeEffects != activation.effects.length;
    if (escapes) {
      for (final state in [activation.normal, activation.exceptional]) {
        if (state != null) _publishExternal(state);
      }
    }
    if (summaryChanged) _pending.addAll(activation.readers);
  }

  // Pruning dead allocation instances is needed at a repeated allocation, not
  // at every syntactic call. A selected call target uses the fixed graph's
  // transitive allocation proof; incomplete or unknown calls remain conservative.
  FlowState _allocationInput(
    _Activation activation,
    Block block,
    Instruction operation,
    List<FlowValue> inputs,
    FlowState state, {
    FlowValue Function(Value)? read,
  }) {
    if (!_loopBlocks(activation.body).contains(block) ||
        _owners[operation] != activation.body.target) {
      return state;
    }
    final liveness = _liveness.putIfAbsent(activation.body.target, () {
      final body = activation.body as IrFunction;
      return ValueLiveness.source(body, calls: {
        for (final block in body.blocks)
          for (final instruction in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ])
            if (instruction is AllocatedObject ||
                instruction.effects.contains(Effect.allocates)) instruction,
      });
    });
    FlowValue retained(Value value) {
      if (read != null) return read(value);
      if (value is Constant) return FlowValue.constant(value);
      if (value case TestedValue(:final test, :final outcome)) {
        return retained(test.operand).check(
          test.testedType.substituteForFlow(activation.executionEnvironment),
          negated: outcome == test.negated,
          runtimeTypes: true,
        ).value;
      }
      return state.resolveValue(
          activation.values[value] ?? FlowValue.unknown(value.type));
    }
    return state.project([
      // The caller can retain aliases detached by this callee. SSA facts may
      // overapproximate a path here; retaining extra capabilities is safe.
      ...activation.input!.allocations,
      ...liveness.acrossCalls[operation]!.map(retained),
      ...inputs,
    ]);
  }

  FlowResult _operation(
    _Activation activation,
    Block block,
    Instruction operation,
    List<FlowValue> inputs,
    FlowState state,
    FlowValue Function(Value) read,
  ) {
    if (inputs.any((value) => value.isBottom)) return _unreachable;
    if (operation.requiredStorageView case final template?) {
      final expected = template.mapTypes(
        (type) => type.substituteForFlow(activation.executionEnvironment),
      );
      // Raw slot copies require the capability on both source and destination.
      final receivers = operation is InitializeStorageField ? inputs : inputs.take(1);
      activation.storageViews[operation] = receivers.every(
        (value) => value.objects.isNotEmpty &&
            value.unknownTypes.isEmpty &&
            value.constants.isEmpty &&
            value.addresses.isEmpty &&
            value.objects.every((object) => object.storageView == expected),
      );
      final read = switch (operation) {
        LoadField(:final field) => (inputs.first, field),
        InitializeStorageField(:final field) => (inputs.last, field),
        _ => null,
      };
      if (read != null && !read.$1.objects.every(
          (object) => state.hasIntactSlot(object, read.$2))) {
        activation.storageViews[operation] = false;
      }
    }
    final resultType = operation.type.substituteForFlow(
      activation.executionEnvironment,
    );
    final folded = _fold(operation, inputs, program, state);
    if (folded != null) {
      activation.operationEffects[operation] = const {};
      final normal = state.copy();
      if (_exceptionSources[state] case final alternatives?) {
        _exceptionSources[normal] = alternatives;
      }
      return FlowResult(value: FlowValue.constant(folded), normal: normal);
    }
    if (!_deferredAllocationProjection(operation) &&
        (operation is AllocatedObject ||
            operation.effects.contains(Effect.allocates))) {
      state = _allocationInput(activation, block, operation, inputs, state,
          read: read);
    }
    FlowObject allocate(Instruction site) {
      final type = site.type.substituteForFlow(activation.executionEnvironment);
      final view = switch (site) {
        Construct(:final storageView) || NewPayload(:final storageView) => storageView,
        ManagedStorageAllocation(:final storageView) => storageView,
        _ => null,
      };
      return FlowObject(site, activation, type: type,
          cellStorage: type is ClassType ? _cellStorages[type.declaration] : null,
          storageView: view?.mapTypes((value) => value.substituteForFlow(activation.executionEnvironment)));
    }
    FlowResult invoke(
      FunctionTarget target,
      List<FlowValue> args,
      FlowState input,
    ) => _invoke(activation, block, operation, target, args, input);
    FlowResult call(
      FlowValue function,
      List<FlowValue> args,
      FlowState input,
    ) => _call(activation, block, operation, function, args, const {}, input);

    final stored = state.transfer(
      operation,
      inputs,
      resultType: resultType,
      allocate: allocate,
      repeated: operation is NativeLocalStorage && activation.recursive,
      invoke: invoke,
      call: call,
    );
    if (stored != null) {
      stored.normal?.rememberRead(
        operation,
        inputs,
        FlowSource(operation, activation),
      );
      activation.operationEffects[operation] = {
        ...stored.effects,
        if (stored.hasSemanticFailure) Effect.mayThrow,
      };
      return stored;
    }
    switch (operation) {
      case MaterializedValue():
        activation.operationEffects[operation] = const {};
        final backing = inputs.last.carrierReferences;
        return FlowResult(
          value: inputs.first.withManagedBackings(
            backing.objects,
            unknown: backing.unknownTypes.isNotEmpty ||
                backing.constants.isNotEmpty || backing.addresses.isNotEmpty,
          ).withSources(const []),
          normal: state.copy(),
        );
      case ConstantCarrier():
        activation.operationEffects[operation] = const {};
        return FlowResult(value: inputs.single, normal: state.copy());
      case FunctionEntryTableAddress(:final target):
        activation.operationEffects[operation] = const {};
        return FlowResult(
          value: FlowValue.address(FlowAddress(target, 0)),
          normal: state.copy(),
        );
      case StackMapAddress():
        return FlowResult(
          value: FlowValue.address(FlowAddress(FlowMetadata.stackMaps, 0)),
          normal: state.copy(),
        );
      case MakeInvocation():
        throw StateError('Normalize Invocation before program flow.');
      case InitializeObject(:final initializer):
        activation.operationEffects[operation] = const {};
        return _invoke(
          activation,
          block,
          operation,
          initializer,
          inputs,
          state,
        );
      case CheckedTypeArgument(
        :final parameter,
        :final environment,
        :final implementation,
      ):
        if (implementation != null) {
          activation.operationEffects[operation] = const {};
          return _invoke(
            activation,
            block,
            operation,
            implementation,
            inputs,
            state,
            resultSource: FlowSource(operation, activation),
          );
        }
        final actual = inputs.first.constant;
        final raw = <TypeParameterType, ValueType>{};
        for (final (index, key) in environment.keys.indexed) {
          if (inputs[index + 1].constant case TypeConstant(
            :final representedType,
          )) {
            raw[key] = representedType;
          }
        }
        final proven =
            actual is TypeConstant && raw.length == environment.length;
        final succeeds =
            !proven ||
            parameter.bound.substitute(raw).accepts(actual.representedType);
        activation.operationEffects[operation] = {
          if (!proven || !succeeds) Effect.mayThrow,
        };
        return FlowResult(
          value: succeeds ? inputs.first : const FlowValue.bottom(),
          normal: succeeds ? state.copy() : null,
          exceptional: !proven || !succeeds ? state.copy() : null,
          exception: !proven || !succeeds
              ? _typeError
              : const FlowValue.bottom(),
        );
      case ManagedStorageAllocation(:final allocator, :final storageView):
        if (allocator != managedAllocator) {
          throw StateError('Invariant storage requires the bound managed allocator.');
        }
        final descriptor = inputs[1];
        if (descriptor.addresses.isEmpty || descriptor.unknownTypes.isNotEmpty ||
            descriptor.constants.isNotEmpty || descriptor.objects.isNotEmpty ||
            descriptor.addresses.any((address) => address.offset != 0 ||
                address.base != storageView.storageType.declaration)) {
          throw StateError('Managed allocation descriptor does not match its storage view.');
        }
        activation.storageViews[operation] = true;
        activation.operationEffects[operation] = const {};
        final actual = invoke(allocator, inputs, state);
        final normal = actual.normal?.copy();
        final object = allocate(operation);
        normal?.acceptManagedAllocation(object, inputs.last,
          repeated: activation.repeated || (_cyclic[activation.body.target]?.contains(block) ?? false));
        return FlowResult(
          value: normal == null ? const FlowValue.bottom() : FlowValue.object(object),
          normal: normal, exceptional: actual.exceptional,
          exception: actual.exception, stackTrace: actual.stackTrace,
          allocationFailureOnly: actual.allocationFailureOnly,
        );
      case DirectCall(
        :final target,
        :final ownerType,
        :final typeArguments,
        :final lexicalEnvironment,
      ):
        final environment = _environment(
          target,
          ownerType,
          typeArguments,
          activation,
        );
        environment.addAll({
          for (final entry in lexicalEnvironment.entries)
            entry.key: entry.value.substitute(activation.executionEnvironment),
        });
        activation.operationEffects[operation] = const {};
        return _invoke(
          activation,
          block,
          operation,
          target,
          inputs,
          state,
          environment: environment,
          resultSource: FlowSource(operation, activation),
        );
      case FunctionCall(:final function, :final positional, :final named):
        activation.operationEffects[operation] = const {};
        return _call(
          activation,
          block,
          operation,
          read(function),
          positional.map(read).toList(),
          named.map((key, value) => MapEntry(key, read(value))),
          state,
          resultSource: FlowSource(operation, activation),
        );
      case InstanceCall(
        :final receiver,
        :final member,
        :final positional,
        :final named,
      ):
        activation.operationEffects[operation] = const {};
        return _dispatch(
          activation,
          block,
          operation,
          member.selector,
          read(receiver),
          positional.map(read).toList(),
          named.map((name, value) => MapEntry(name, read(value))),
          operation.typeArguments,
          state,
          executionTypes: operation.executionTypes.map(read).toList(),
          resultSource: FlowSource(operation, activation),
        );
      case DynamicDispatch(
        :final receiver,
        :final selector,
        :final positional,
        :final named,
        :final typeArguments,
      ):
        activation.operationEffects[operation] = const {};
        return _dispatch(
          activation,
          block,
          operation,
          selector,
          read(receiver),
          positional.map(read).toList(),
          named.map((name, value) => MapEntry(name, read(value))),
          typeArguments,
          state,
          checkAllArguments: true,
          resultSource: FlowSource(operation, activation),
        );
      case BindMethod(:final method, :final receiver, :final direct):
        activation.operationEffects[operation] = const {};
        var result = _unreachable;
        var found = false;
        for (final type in _receiverTypes(read(receiver))) {
          found = true;
          final target = direct
              ? method
              : program.lookupMember(type, method.selector).target;
          if (target != null && (target.isAbstract || program.implementationOf(target) == null)) {
            throw StateError('Method extraction requires its actual source body.');
          }
          result = _joinResult(
            result,
            target == null
                ? FlowResult(
                    value: FlowValue.unknown(resultType),
                    normal: state.copy(),
                    exceptional: state.copy(),
                  )
                : _bindAtType(
                    activation,
                    block,
                    operation,
                    target,
                    type,
                    read(receiver),
                    state,
                    executionTypes: operation.executionTypes.map(read).toList(),
                  ),
          );
        }
        return found
            ? result
            : FlowResult(
                value: FlowValue.unknown(resultType),
                normal: state.copy(),
                exceptional: state.copy(),
              );
      case final ReadFunctionTypeArgument argumentRead:
        final result = _readTypeArgument(
          argumentRead,
          read(argumentRead.function),
          state,
        );
        activation.environmentReads[operation] = result.proven;
        return FlowResult(value: result.value, normal: state.copy());
      case final ReadFunctionEnvironment environmentRead:
        final result = _readEnvironment(
          environmentRead,
          read(environmentRead.function),
          state,
        );
        activation.environmentReads[operation] = result.proven;
        return FlowResult(value: result.value, normal: state.copy());
      case InstantiateFunction(:final function, :final typeArguments):
        return _instantiate(
          activation,
          operation,
          read(function),
          [
            for (final type in typeArguments)
              type.substitute(activation.executionEnvironment),
          ],
          state,
          repeated: false,
        );
      case InstantiateFunctionFrom(
        :final function,
        :final instance,
        :final declaration,
      ):
        FlowResult result = _unreachable;
        for (final type in _receiverTypes(read(instance))) {
          final view = type.asInstanceOf(declaration);
          if (view == null) continue;
          result = _joinResult(
            result,
            _instantiate(
              activation,
              operation,
              read(function),
              view.typeArguments,
              state,
              repeated: false,
            ),
          );
        }
        return result;
      case NativeCallbackAddress(:final target):
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: FlowValue.address(FlowAddress(target, 0)),
          normal: state.copy(),
        );
      case NativeCall(:final signature) || RawNativeCall(:final signature)
          when signature.result is! NativeCompoundType &&
              !signature.parameters.any((type) => type is NativeCompoundType):
        // The native ABI transports scalar values and pointers. Foreign code
        // may retain and overwrite reachable storage, and call exported Dart
        // functions, which expose their ordinary effects through re-entry.
        activation.operationEffects[operation] = operation.effects;
        activation.externalCalls.add(operation);
        return _external(
          activation,
          block,
          operation,
          inputs,
          state,
          resultType,
          nativeScalarCall: true,
          returned: resultType == .voidType ? _null : null,
        );
      case ReferenceAddress():
        activation.operationEffects[operation] = const {Effect.readsStorage};
        return FlowResult(
          value: _referenceAddress(inputs.single),
          normal: state.copy(),
        );
      case PointerFromAddress() || PointerAddress():
        final input = inputs.single;
        var value = const FlowValue.bottom();
        for (final address in input.addresses) {
          value = value.join(
            FlowValue.address(
              FlowAddress.ranged(
                address.base,
                address.offsets,
                type: resultType,
                retainedBase: address.retainedBase,
              ),
            ),
          );
        }
        if (input.constants.isNotEmpty ||
            input.objects.isNotEmpty ||
            input.unknownTypes.isNotEmpty) {
          value = value.join(FlowValue.unknown(resultType));
        }
        if (operation is PointerAddress) {
          for (final source in input.sources) {
            if (source.value case PointerFromAddress(:final address)
                when source.activation is _Activation) {
              final creator = source.activation as _Activation;
              value = address is Constant
                  ? FlowValue.constant(address)
                  : creator.values[address] ?? value;
              break;
            }
          }
        }
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: value.withReferences([input.references]),
          normal: state.copy(),
        );
      case PointerOffset():
        final input = inputs.first;
        final layout = memoryLayout?.nativeLayout;
        final index = inputs.last.integers;
        final stride = layout?.of(FfiTypes.pointerElement(resultType)!).size;
        FlowIntegerRange? amount;
        if (index != null && stride != null) {
          final count = index.constant;
          amount = count == null
              ? index.multiply(FlowIntegerRange(stride, stride))
              : FlowIntegerRange(count * stride, count * stride);
        }
        var value = const FlowValue.bottom();
        for (final address in input.addresses) {
          value = value.join(
            FlowValue.address(
              FlowAddress.ranged(
                address.base,
                _shiftOffsets(
                  address.offsets,
                  amount,
                  bits: (layout?.target.wordSize ?? 8) * 8,
                ),
                type: resultType,
                retainedBase: address.retainedBase,
              ),
            ),
          );
        }
        if (input.unknownTypes.isNotEmpty ||
            input.objects.isNotEmpty ||
            input.constants.isNotEmpty) {
          value = value.join(FlowValue.unknown(resultType));
        }
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: value.withReferences([input.references]),
          normal: state.copy(),
        );
      case ReferenceFromAddress():
        final input = inputs.single;
        if (ExecutionShapes.forType(resultType).isScalar) {
          var scalar = const FlowValue.bottom();
          for (final address in input.addresses) {
            scalar = scalar.join(switch (address) {
              FlowAddress(base: final FlowObject backing, offset: 0) =>
                FlowValue.unknown(resultType).withManagedBackings([backing]),
              FlowAddress(base: final ScalarConstant constant, offset: 0)
                  when resultType.accepts(constant.type) =>
                FlowValue.constant(constant),
              _ => FlowValue.unknown(resultType)
                  .withManagedBackings(const [], unknown: true),
            });
          }
          if (input.unknownTypes.isNotEmpty || input.objects.isNotEmpty ||
              input.constants.isNotEmpty || scalar.isBottom) {
            scalar = scalar.join(FlowValue.unknown(resultType)
                .withManagedBackings(const [], unknown: true));
          }
          activation.operationEffects[operation] = const {Effect.readsStorage};
          return FlowResult(
            value: scalar.withReferences([input.references]),
            normal: state.copy(),
          );
        }
        var value = const FlowValue.bottom();
        for (final address in input.addresses) {
          value = value.join(
            address.offset == 0 &&
                    (address.base is FlowObject || address.base is Constant)
                ? address.reference.check(resultType).value
                : FlowValue.unknown(resultType)
                      .withReferences([address.reference]),
          );
        }
        for (final constant in input.constants) {
          value = value.join(
            constant is ScalarConstant &&
                    constant.value == 0 &&
                    resultType.mayBeNull
                ? FlowValue.constant(const Constant.nullValue())
                : FlowValue.unknown(resultType),
          );
        }
        if (input.unknownTypes.isNotEmpty || input.objects.isNotEmpty) {
          value = value.join(FlowValue.unknown(resultType));
        }
        for (final source in input.sources) {
          if (source.value case ReferenceAddress(:final object)
              when source.activation is _Activation) {
            final creator = source.activation as _Activation;
            value = object is Constant
                ? FlowValue.constant(object)
                : creator.values[object] ?? value;
            value = value.check(resultType).value;
            break;
          }
        }
        if (value.isBottom) value = FlowValue.unknown(resultType);
        activation.operationEffects[operation] = const {Effect.readsStorage};
        return FlowResult(
          value: value.withReferences([input.references]),
          normal: state.copy(),
        );
      case IntBinary(operator: .add || .subtract)
          when inputs.any((input) => input.addresses.isNotEmpty):
        activation.operationEffects[operation] = const {};
        return FlowResult(
          value: _addressArithmetic(operation, inputs),
          normal: state.copy(),
        );
      case ObjectRuntimeType(direct: true):
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: _runtimeTypeValue(inputs.single, state),
          normal: state.copy(),
        );
      case ReifyType(:final template):
        if (activation.body case IrFunction(:final typeBindings)) {
          for (final binding in typeBindings) {
            if (template == binding.parameter) {
              activation.operationEffects[operation] = const {};
              return FlowResult(
                value: read(binding.value),
                normal: state.copy(),
              );
            }
          }
        }
        final type = template.substitute(activation.executionEnvironment);
        if (type.freeTypeParameters.isEmpty) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: FlowValue.constant(TypeConstant(type)),
            normal: state.copy(),
          );
        }
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: FlowValue.unknown(.typeType),
          normal: state.copy(),
        );
      case TypeTest(:final testedType, :final negated):
        final expected = testedType.substituteForFlow(
          activation.executionEnvironment,
        );
        final checked = inputs.single.check(expected, runtimeTypes: true,
            runtimeTypeOf: (object) => _callableRuntimeType(object, state));
        final matches = !checked.mayFail
            ? true
            : checked.value.isBottom
            ? false
            : null;
        if (matches != null) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: FlowValue.constant(Constant.boolean(matches != negated)),
            normal: state.copy(),
          );
        }
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: FlowValue.unknown(.boolean),
          normal: state.copy(),
          exceptional: operation.effects.contains(Effect.mayThrow)
              ? state.copy()
              : null,
        );
      case TypeCast() || NullCheck():
        final checked = inputs.single.check(
          operation is NullCheck ? ValueType.object : resultType,
          runtimeTypes: true,
          runtimeTypeOf: (object) => _callableRuntimeType(object, state),
        );
        activation.operationEffects[operation] = {
          if (checked.mayFail) Effect.mayThrow,
        };
        return FlowResult(
          value: checked.value,
          normal: checked.value.isBottom ? null : state.copy(),
          exceptional: checked.mayFail ? state.copy() : null,
          exception: _typeError,
        );
      case CellReference() || CallableReference() || CellStorageView() || CellStorageReference():
        activation.operationEffects[operation] = const {};
        return FlowResult(value: inputs.single, normal: state.copy());
      case TypeView() || UncheckedCast():
        final value = inputs.single.check(resultType).value;
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: value,
          normal: value.isBottom ? null : state.copy(),
        );
      default:
        if (operation is Equals &&
            inputs.first.runtimeTypes.every(
              (type) => type == TypeMetadata.type,
            )) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: FlowValue.unknown(.boolean),
            normal: state.copy(),
          );
        }
        if (_integerOperation(operation, inputs) case final result?) {
          activation.operationEffects[operation] = {
            if (result.mayThrow) Effect.mayThrow,
          };
          return FlowResult(
            // A predicate produces a boolean, not an address derived from its
            // operands. Integer arithmetic still retains raw capabilities.
            value: resultType == .boolean
                ? result.value
                : result.value.withReferences(
                    inputs.map((value) => value.references),
                  ),
            normal: result.value.isBottom ? null : state.copy(),
            exceptional: result.mayThrow ? state.copy() : null,
          );
        }
        activation.operationEffects[operation] = operation.effects;
        if (operation.effects.contains(Effect.callsUserCode)) {
          if (operation.implicitMember case final member?) {
            activation.operationEffects[operation] = const {};
            final result = _dispatch(
              activation,
              block,
              operation,
              member.selector,
              inputs.first,
              inputs.skip(1).toList(),
              const {},
              const [],
              state,
            );
            if (operation case Equals(negated: true)) {
              final value = result.value.constant;
              return FlowResult(
                value: value is ScalarConstant && value.value is bool
                    ? FlowValue.constant(
                        Constant.boolean(!(value.value as bool)),
                      )
                    : result.value,
                normal: result.normal,
                exceptional: result.exceptional,
                allocationFailureOnly: result.allocationFailureOnly,
                exception: result.exception,
                stackTrace: result.stackTrace,
              );
            }
            return result;
          }
          activation.unknownCalls.add(operation);
          return _external(
            activation,
            block,
            operation,
            inputs,
            state,
            resultType,
            accessesProgramState: true,
          );
        }
        final next = state.copy();
        if (operation.effects.contains(Effect.writesStorage)) {
          next.invalidate(inputs);
        }
        return FlowResult(
          value: resultType == .never
              ? const FlowValue.bottom()
              : FlowValue.unknown(resultType)
                    .withReferences(resultType == .boolean
                        ? const []
                        : inputs.map((value) => value.references)),
          normal: resultType == .never ? null : next,
          exceptional: operation.effects.contains(Effect.mayThrow)
              ? next.copy()
              : null,
        );
    }
  }

  FlowResult _dispatch(
    _Activation activation,
    Block block,
    Instruction operation,
    MemberSelector selector,
    FlowValue receiver,
    List<FlowValue> positional,
    Map<String, FlowValue> named,
    List<ValueType> typeArguments,
    FlowState state, {
    bool checkAllArguments = false,
    FlowSource? resultSource,
    List<FlowValue> executionTypes = const [],
  }) {
    var result = _unreachable;
    var unresolved = false;
    var found = false;
    final functionCall =
        selector.name == 'call' &&
        selector.privateScope == null &&
        selector.kind != .setter;
    if (functionCall) {
      var functions = const FlowValue.bottom();
      for (final constant in receiver.constants.whereType<FunctionConstant>()) {
        functions = functions.join(FlowValue.constant(constant));
      }
      for (final object in receiver.objects.where(
        (object) => object.type is FunctionType || object.callableStorage != null,
      )) {
        functions = functions.join(FlowValue.object(object));
      }
      for (final type in receiver.unknownTypes) {
        if (type.nonNullable is FunctionType ||
            type.nonNullable == ValueType.function) {
          functions = functions.join(FlowValue.unknown(type.nonNullable));
        }
      }
      if (!functions.isBottom) {
        found = true;
        result = _joinResult(
          result,
          selector.kind == .getter
              ? FlowResult(value: functions, normal: state.copy())
              : _call(
                  activation,
                  block,
                  operation,
                  functions,
                  positional,
                  named,
                  state,
                  typeArguments: typeArguments,
                  checkAllArguments: checkAllArguments,
                  resultSource: resultSource,
                ),
        );
      }
    }
    for (final type in _receiverTypes(receiver)) {
      if (functionCall && type == ValueType.function) continue;
      found = true;
      final lookup = program.lookupMember(type, selector);
      final target = lookup.target;
      if (target == null && selector.kind == .getter) {
        final method = program.lookupMember(type, (
          kind: .method,
          name: selector.name,
          privateScope: selector.privateScope,
        )).target;
        if (method != null) {
          if (operation case DynamicDispatch(methodBindings: final bindings)
              when bindings.containsKey(method)) {
            final implementation = bindings[method]!;
            result = _joinResult(result, _invoke(activation, block, operation,
                implementation, [_receiverValue(receiver, type)], state,
                resultSource: resultSource));
            continue;
          }
          result = _joinResult(
            result,
            _bindAtType(
              activation,
              block,
              operation,
              method,
              type,
              receiver,
              state,
            ),
          );
          continue;
        }
      }
      if (target == null &&
          selector.kind == .method &&
          operation is DynamicDispatch) {
        final getter = program.lookupMember(type, (
          kind: FunctionKind.getter,
          name: selector.name,
          privateScope: selector.privateScope,
        )).target;
        if (getter != null && program.implementationOf(getter) != null) {
          final helper =
              operation.getterCalls[getter] ??
              (throw StateError('Normalize getter calls before program flow.'));
          result = _joinResult(
            result,
            _invoke(
              activation,
              block,
              operation,
              helper,
              [_receiverValue(receiver, type), ...positional, ...named.values],
              state,
              environment: _environment(
                helper,
                null,
                typeArguments,
                activation,
              ),
              resultSource: resultSource,
            ),
          );
          continue;
        }
      }
      if (target == null || lookup.unsupportedForwarder) {
        final missing = _noSuchMethod(
          activation,
          block,
          operation,
          type,
          selector,
          receiver,
          positional,
          named,
          state,
          resultSource: resultSource,
        );
        if (missing == null) {
          unresolved = true;
        } else {
          result = _joinResult(result, missing);
        }
        continue;
      }
      final body = program.implementationOf(target);
      if (body == null) {
        unresolved = true;
        continue;
      }
      if (!target.signature.acceptsShape(positional.length, named.keys) ||
          typeArguments.isNotEmpty &&
              typeArguments.length != target.typeParameters.length) {
        final missing = _noSuchMethod(
          activation,
          block,
          operation,
          type,
          selector,
          receiver,
          positional,
          named,
          state,
          resultSource: resultSource,
        );
        if (missing == null) {
          unresolved = true;
        } else {
          result = _joinResult(result, missing);
        }
        continue;
      }
      if (operation is InstanceCall) {
        (activation.callableSources[operation] ??= {}).add(target);
        final binding = operation.entryBinding;
        final entry = binding?.entries[target];
        if (entry != null) {
          result = _joinResult(result, _invoke(activation, block, operation,
            entry, [_receiverValue(receiver, type), ...positional,
              for (final name in binding!.names) named[name]!, ...executionTypes],
            state, resultSource: resultSource));
          continue;
        }
        (activation.pendingExecution[operation] ??= {}).add(target);
      }
      final arguments = target.signature.bind<FlowValue>(
        positional,
        named,
        (index) => FlowValue.constant(body.defaults[index]!),
      );
      final appliedTypes = [
        for (final argument
            in typeArguments.isEmpty && checkAllArguments
                ? target.typeParameters.map(
                    (parameter) => parameter.defaultType ?? parameter.bound,
                  )
                : typeArguments)
          argument.substitute(activation.executionEnvironment),
      ];
      try {
        target.signatureFor(type).instantiate(appliedTypes);
      } on ArgumentError {
        result = _joinResult(result, FlowResult(exceptional: state.copy()));
        activation.operationEffects[operation] = {
          ...?activation.operationEffects[operation],
          Effect.mayThrow,
        };
        continue;
      }
      final invoked = _invoke(
        activation,
        block,
        operation,
        target,
        [_receiverValue(receiver, type), ...arguments],
        state,
        environment: _environment(target, type, appliedTypes, activation),
        checkAllArguments: checkAllArguments,
        resultSource: resultSource,
      );
      if (target.requiresResultCheck && invoked.normal != null) {
        final checked = invoked.value.check(
          operation.type.substituteForFlow(activation.executionEnvironment),
          runtimeTypes: true,
        );
        result = _joinResult(
          result,
          FlowResult(
            value: checked.value,
            normal: checked.value.isBottom ? null : invoked.normal,
            exceptional: checked.mayFail
                ? _joinState(invoked.exceptional, invoked.normal)
                : invoked.exceptional,
            allocationFailureOnly:
                !checked.mayFail && invoked.allocationFailureOnly,
            exception: checked.mayFail
                ? invoked.exception.join(FlowValue.unknown(.object))
                : invoked.exception,
            stackTrace: checked.mayFail
                ? invoked.stackTrace.join(FlowValue.unknown(.stackTrace))
                : invoked.stackTrace,
          ),
        );
      } else {
        result = _joinResult(result, invoked);
      }
    }
    if (unresolved || !found) {
      activation.unknownCalls.add(operation);
      result = _joinResult(
        result,
        _external(
          activation,
          block,
          operation,
          [receiver, ...positional, ...named.values],
          state,
          operation.type.substituteForFlow(activation.executionEnvironment),
          accessesProgramState: true,
        ),
      );
    }
    return result;
  }

  FlowResult _bindAtType(
    _Activation activation,
    Block block,
    Instruction site,
    FunctionTarget target,
    ClassType receiverType,
    FlowValue receiver,
    FlowState state, {
    List<FlowValue> executionTypes = const [],
  }
  ) {
    if (site is BindMethod) {
      (activation.callableSources[site] ??= {}).add(target);
      final entry = site.entryBinding?.entries[target];
      if (entry != null) {
        if (program.implementationOf(entry) is! IrFunction) {
          throw StateError('A method producer requires its actual ordinary body.');
        }
        return _invoke(activation, block, site, entry, [
          _receiverValue(receiver, receiverType),
          ...executionTypes,
        ], state, resultSource: FlowSource(site, activation));
      }
      (activation.pendingExecution[site] ??= {}).add(target);
    }
    final actual = target.reifiedSignature
        .substitute(target.environmentFor(receiverType))
        .reify();
    final expected = site.type
        .substitute(activation.executionEnvironment)
        .runtimeCheckType;
    final unresolved =
        actual.freeTypeParameters.isNotEmpty ||
        expected.freeTypeParameters.isNotEmpty;
    if (!unresolved && !expected.accepts(actual)) {
      activation.operationEffects[site] = {
        ...?activation.operationEffects[site],
        Effect.mayThrow,
      };
      return FlowResult(exceptional: state.copy());
    }
    final object = FlowObject(site, activation, type: actual, variant: target);
    final next = state.copy()
      ..retain(object, [
        _receiverValue(receiver, receiverType),
      ], repeated: false);
    activation.boundMethods.putIfAbsent(object, () => {}).add(target);
    activation.operationEffects[site] = {
      ...?activation.operationEffects[site],
      Effect.allocates,
      if (unresolved) Effect.mayThrow,
    };
    return FlowResult(
      value: FlowValue.object(object),
      normal: next,
      exceptional: unresolved ? state.copy() : null,
    );
  }

  FlowResult? _noSuchMethod(
    _Activation activation,
    Block block,
    Instruction operation,
    ClassType receiverType,
    MemberSelector selector,
    FlowValue receiver,
    List<FlowValue> positional,
    Map<String, FlowValue> named,
    FlowState state, {
    FlowSource? resultSource,
  }) {
    if (operation case DynamicDispatch(:final failure?, :final typeArguments)) {
      return _invoke(
        activation,
        block,
        operation,
        failure,
        [
          _receiverValue(receiver, receiverType),
          ...positional,
          ...named.values,
        ],
        state,
        environment: _environment(failure, null, typeArguments, activation),
        resultSource: resultSource,
      );
    }
    final target = program.lookupMember(receiverType, (
      kind: FunctionKind.method,
      name: 'noSuchMethod',
      privateScope: null,
    )).target;
    if (target == null || program.implementationOf(target) == null) return null;
    throw StateError(
      'Missing normalized ${operation.runtimeType} ${selector.name} '
      'on ${receiverType.dartName} in ${activation.body.target.name}.',
    );
  }

  FlowResult _instantiate(
    _Activation activation,
    Instruction site,
    FlowValue function,
    List<ValueType> arguments,
    FlowState state, {
    required bool repeated,
  }) {
    var value = const FlowValue.bottom();
    var mayFail = false;
    final next = state.copy();
    void bind(FlowValue origin, FunctionType signature, Object variant) {
      FunctionType applied;
      try {
        applied = signature.instantiate(arguments);
      } on ArgumentError {
        mayFail = true;
        return;
      }
      final object = FlowObject(
        site,
        activation,
        type: applied,
        variant: (variant, _typeKey(arguments)),
      );
      next.retain(object, [origin], repeated: repeated);
      activation.instantiations[object] = arguments;
      value = value.join(FlowValue.object(object));
    }

    for (final constant in function.constants.whereType<FunctionConstant>()) {
      if (arguments.every((type) => type.freeTypeParameters.isEmpty)) {
        try {
          value = value.join(
            FlowValue.constant(
              FunctionConstant(
                constant.target,
                ownerType: constant.ownerType,
                typeArguments: arguments,
                constructorSignature: constant.constructorSignature,
                constructorAlias: constant.constructorAlias,
                constructorTypeArguments: constant.constructorTypeArguments,
                invocationEntry: constant.invocationEntry,
              ),
            ),
          );
        } on ArgumentError {
          mayFail = true;
        }
      } else {
        bind(
          FlowValue.constant(constant),
          constant.type as FunctionType,
          constant.structuralKey,
        );
      }
    }
    for (final object in function.objects) {
      if (object.type is FunctionType) {
        bind(FlowValue.object(object), object.type as FunctionType, object);
      } else {
        mayFail = true;
      }
    }
    if (function.unknownTypes.isNotEmpty) {
      value = value.join(
        FlowValue.unknown(
          site.type.substituteForFlow(activation.executionEnvironment),
        ),
      );
      mayFail = true;
    }
    activation.operationEffects[site] = {
      if (value.objects.isNotEmpty || value.unknownTypes.isNotEmpty)
        Effect.allocates,
      if (mayFail) Effect.mayThrow,
    };
    return FlowResult(
      value: value,
      normal: value.isBottom ? null : next,
      exceptional: mayFail ? state.copy() : null,
    );
  }

  Map<TypeParameterType, ValueType> _environment(
    FunctionTarget target,
    ClassType? owner,
    Iterable<ValueType> arguments,
    _Activation caller,
  ) => {
    if (owner != null)
      ...target.environmentFor(
        owner.substitute(caller.executionEnvironment) as ClassType,
      ),
    for (final (index, type) in arguments.indexed)
      target.typeParameters[index]: type.substitute(
        caller.executionEnvironment,
      ),
  };

  FlowResult _call(
    _Activation activation,
    Block block,
    Instruction site,
    FlowValue function,
    List<FlowValue> positional,
    Map<String, FlowValue> named,
    FlowState state, {
    List<ValueType>? typeArguments,
    bool checkAllArguments = false,
    FlowSource? resultSource,
    FlowValue? invocationEnvironment,
    List<FlowValue>? descriptorArguments,
  }) {
    FlowResult result = _unreachable;
    final appliedArguments = [
      for (final type
          in typeArguments ??
              (site is FunctionCall ? site.typeArguments : const <ValueType>[]))
        type.substitute(activation.executionEnvironment),
    ];
    bool accepts(FlowValue receiver, FunctionType signature) {
      if (signature.acceptsShape(positional.length, named.keys) &&
          (appliedArguments.isEmpty ||
              appliedArguments.length == signature.typeParameters.length)) {
        return true;
      }
      if (site case DynamicDispatch(:final failure?, :final typeArguments)) {
        result = _joinResult(
          result,
          _invoke(
            activation,
            block,
            site,
            failure,
            [receiver, ...positional, ...named.values],
            state,
            environment: _environment(failure, null, typeArguments, activation),
            resultSource: resultSource,
          ),
        );
      } else {
        result = _joinResult(result, FlowResult(exceptional: state.copy()));
        activation.operationEffects[site] = {
          ...?activation.operationEffects[site],
          Effect.mayThrow,
        };
      }
      return false;
    }

    List<FlowValue> bind(FunctionTarget target, IrCallable? body) =>
        target.signature.bind<FlowValue>(
          positional,
          named,
          (index) => FlowValue.constant(body!.defaults[index]!),
        );

    FlowResult? entryFor(FunctionTarget source, FlowValue receiver) {
      (activation.callableSources[site] ??= {}).add(source);
      final binding = switch (site) {
        FunctionCall(:final entryBinding) || DynamicDispatch(:final entryBinding) => entryBinding,
        _ => null,
      };
      final entry = binding?.entries[source];
      if (entry == null) {
        // This is a known semantic call, with an actual source body and input
        // state. It is not an unknown external invocation. Keep analyzing that
        // source while the implementation owner fulfills this explicit demand;
        // final preparation must reject any demand left unfulfilled.
        (activation.pendingExecution[site] ??= {}).add(source);
        return null;
      }
      final result = _invoke(
        activation,
        block,
        site,
        entry,
        [
          invocationEnvironment ?? receiver,
          ...positional,
          for (final name in binding!.shape.named.keys) named[name]!,
          for (final argument in switch (site) {
            FunctionCall(:final typeArguments) || DynamicDispatch(:final typeArguments) => typeArguments,
            _ => const <ValueType>[],
          })
            if (argument.substitute(activation.executionEnvironment)
                case final type when type.freeTypeParameters.isEmpty)
              FlowValue.constant(TypeConstant(type))
            else
              FlowValue.unknown(TypeMetadata.type),
        ],
        state,
        resultSource: resultSource,
      );
      return result;
    }

    for (final constant in function.constants.whereType<FunctionConstant>()) {
      final actualSource = constant.invocationEntry ?? constant.target.implementation;
      (activation.callableSources[site] ??= {}).add(actualSource);
      if (site is DynamicDispatch && site.entryBinding != null) {
        if (entryFor(actualSource, FlowValue.constant(constant)) case final invoked?) {
          result = _joinResult(result, invoked);
          continue;
        }
      }
      final signature = constant.type as FunctionType;
      if (descriptorArguments != null &&
          descriptorArguments.length != signature.typeParameters.length) {
        activation.unknownCalls.add(site);
        continue;
      }
      if (!accepts(FlowValue.constant(constant), signature)) continue;
      final effective = descriptorArguments != null
          ? [for (final (index, descriptor) in descriptorArguments.indexed)
              switch (descriptor.constant) {
                TypeConstant(:final representedType) => representedType,
                _ => signature.typeParameters[index],
              }]
          : appliedArguments.isEmpty && checkAllArguments
          ? [
              for (final parameter in signature.typeParameters)
                parameter.defaultType ?? parameter.bound,
            ]
          : appliedArguments;
      // The source is known even when its generic argument check must fail.
      // A mapped entry owns that check, so it must execute before resolving the
      // source's validated generic signature.
      if (constant.target.kind != .initializer &&
              constant.target.kind != .factory ||
          constant.invocationEntry != null) {
        final source =
            constant.invocationEntry ?? constant.target.implementation;
        if (entryFor(source, FlowValue.constant(constant))
            case final invoked?) {
          result = _joinResult(result, invoked);
          continue;
        }
      }
      late final ({
        FunctionTarget target,
        ClassType? owner,
        List<ValueType> typeArguments,
      })
      binding;
      try {
        binding = constant.resolveInvocation(effective);
      } on ArgumentError {
        result = _joinResult(result, FlowResult(exceptional: state.copy()));
        activation.operationEffects[site] = {
          ...?activation.operationEffects[site],
          Effect.mayThrow,
        };
        continue;
      }
      final (:target, :owner, typeArguments: genericArguments) = binding;
      if (entryFor(target, FlowValue.constant(constant)) case final invoked?) {
        result = _joinResult(result, invoked);
        continue;
      }
      final body = program.implementationOf(target);
      final arguments = bind(target, body);
      final environment = _environment(
        target,
        owner,
        genericArguments,
        activation,
      );
      final FlowResult invoked;
      if (target.kind == .initializer) {
        activation.operationEffects[site] = {
          ...?activation.operationEffects[site],
          Effect.allocates,
        };
        invoked = state.construct(
          FlowObject(
            site,
            activation,
            type: owner!.substituteForFlow(activation.executionEnvironment),
          ),
          target,
          arguments,
          repeated: false,
          invoke: (target, arguments, input) => _invoke(
            activation,
            block,
            site,
            target,
            arguments,
            input,
            environment: environment,
            checkAllArguments: checkAllArguments,
          ),
        );
      } else {
        invoked = _invoke(
          activation,
          block,
          site,
          target,
          arguments,
          state,
          environment: environment,
          checkAllArguments: checkAllArguments,
          resultSource: resultSource,
        );
      }
      result = _joinResult(result, invoked);
    }
    for (final object in function.objects) {
      if (object.site is InstantiateFunction || object.site is InstantiateFunctionFrom) {
        final origin = state.capturesOf(object);
        if (origin == null) { activation.unknownCalls.add(site); continue; }
        result = _joinResult(result, _call(activation, block, site, origin.single,
            positional, named, state,
            typeArguments: _creator(object).instantiations[_original(object)]!,
            checkAllArguments: checkAllArguments, resultSource: resultSource,
            invocationEnvironment: invocationEnvironment ?? FlowValue.object(object)));
        continue;
      }
      final sources = switch (object.site) {
        MakeClosure(:final target) => {target},
        BindMethod() || DynamicDispatch() =>
          _creator(object).boundMethods[_original(object)] ?? <FunctionTarget>{},
        _ => <FunctionTarget>{},
      };
      var invokedEveryEntry = sources.isNotEmpty;
      for (final source in sources) {
        if (entryFor(source, FlowValue.object(object)) case final invoked?) {
          result = _joinResult(result, invoked);
        } else {
          invokedEveryEntry = false;
        }
      }
      if (invokedEveryEntry) continue;
      if (object.callableStorage case final storage? when storage.origin != null) {
        final origin = state.storedFieldOf(object, storage.origin!);
        final arguments = _storedArguments(object, state);
        if (origin == null || arguments == null) {
          activation.unknownCalls.add(site);
          continue;
        }
        result = _joinResult(result, _call(activation, block, site, origin,
            positional, named, state, descriptorArguments: arguments,
            checkAllArguments: checkAllArguments, resultSource: resultSource,
            invocationEnvironment: invocationEnvironment ?? FlowValue.object(object)));
        continue;
      }
      if (object.callableStorage?.source case final source?
          when _provesStoredCallable(object, state, source)) {
        if (entryFor(source, FlowValue.object(object)) case final invoked?) {
          result = _joinResult(result, invoked);
          continue;
        }
      }
      final signature = object.callableStorage?.signature ?? object.type as FunctionType;
      if (descriptorArguments != null &&
          descriptorArguments.length != signature.typeParameters.length) {
        activation.unknownCalls.add(site);
        continue;
      }
      if (!accepts(FlowValue.object(object), signature)) continue;
      final effective = descriptorArguments != null
          ? [for (final (index, descriptor) in descriptorArguments.indexed)
              switch (descriptor.constant) {
                TypeConstant(:final representedType) => representedType,
                _ => signature.typeParameters[index],
              }]
          : appliedArguments.isEmpty && checkAllArguments
          ? signature.defaultTypeArguments
          : appliedArguments;
      try {
        signature.instantiate(effective);
      } on ArgumentError {
        result = _joinResult(result, FlowResult(exceptional: state.copy()));
        activation.operationEffects[site] = {
          ...?activation.operationEffects[site],
          Effect.mayThrow,
        };
        continue;
      }
      final captures = state.capturesOf(object);
      if (captures == null) {
        activation.unknownCalls.add(site);
        continue;
      }
      switch (object.site) {
        case Construct(callableStorage: final storage?) ||
            AllocatedObject(callableStorage: final storage?):
          final target = storage.source;
          if (target == null) throw StateError('Unresolved callable wrapper.');
          if (!_provesStoredCallable(object, state, target)) {
            activation.unknownCalls.add(site);
            continue;
          }
          if (entryFor(target, FlowValue.object(object)) case final invoked?) {
            result = _joinResult(result, invoked);
            continue;
          }
          final body = program.implementationOf(target)!;
          final environment = <TypeParameterType, ValueType>{
            for (final (i, parameter) in storage.parameters.indexed)
              parameter: switch (state
                  .storedFieldOf(object, storage.descriptors[i])
                  ?.constant) {
                TypeConstant(:final representedType) => representedType,
                _ => parameter,
              },
            ..._environment(target, null, effective, activation),
          };
          result = _joinResult(
            result,
            _invoke(
              activation,
              block,
              site,
              target,
              [
                if (target.kind == .closure) FlowValue.object(object),
                ...captures,
                ...bind(target, body),
              ],
              state,
              environment: environment,
              checkAllArguments: checkAllArguments,
              resultSource: resultSource,
            ),
          );
        case MakeClosure(:final target):
          if (entryFor(target, FlowValue.object(object)) case final invoked?) {
            result = _joinResult(result, invoked);
            continue;
          }
          final body = program.implementationOf(target)!;
          final arguments = bind(target, body);
          result = _joinResult(
            result,
            _invoke(
              activation,
              block,
              site,
              target,
              [FlowValue.object(object), ...captures, ...arguments],
              state,
              environment: {
                ..._creator(object).executionEnvironment,
                ..._environment(target, null, effective, activation),
              },
              checkAllArguments: checkAllArguments,
              resultSource: resultSource,
            ),
          );
        case BindMethod() || DynamicDispatch():
          final creator = _creator(object);
          for (final target
              in creator.boundMethods[_original(object)] ??
                  <FunctionTarget>{}) {
            if (entryFor(target, FlowValue.object(object))
                case final invoked?) {
              result = _joinResult(result, invoked);
              continue;
            }
            final body = program.implementationOf(target)!;
            final arguments = bind(target, body);
            result = _joinResult(
              result,
              _invoke(
                activation,
                block,
                site,
                target,
                [...captures, ...arguments],
                state,
                environment: _environment(target, null, effective, activation),
                checkAllArguments: checkAllArguments,
                resultSource: resultSource,
              ),
            );
          }
        default:
          activation.unknownCalls.add(site);
      }
    }
    if (function.unknownTypes.isNotEmpty ||
        activation.unknownCalls.contains(site)) {
      if (site case FunctionCall(target: final bound?)) {
        throw StateError(
          'Unresolved function value for proven target ${bound.name}.',
        );
      }
      activation.unknownCalls.add(site);
      result = _joinResult(
        result,
        _external(
          activation,
          block,
          site,
          [function, ...positional, ...named.values],
          state,
          site.type.substituteForFlow(activation.executionEnvironment),
          accessesProgramState: true,
        ),
      );
    }
    return result;
  }

  FlowResult _external(
    _Activation activation,
    Block block,
    Instruction operation,
    List<FlowValue> inputs,
    FlowState state,
    ValueType resultType, {
    Set<Effect>? effects,
    ExternalMemory memory = const .arbitrary(),
    bool capturesArguments = true,
    // An unknown Dart invocation can name module storage without receiving it
    // as an argument. Explicit external leaves keep their own memory contract.
    bool accessesProgramState = false,
    bool nativeScalarCall = false,
    FlowValue? returned,
    bool allocationProjected = false,
  }) {
    effects ??= operation.effects;
    if (!allocationProjected && _deferredAllocationProjection(operation) &&
        (effects.contains(Effect.allocates) ||
            effects.contains(Effect.callsUserCode))) {
      state = _allocationInput(activation, block, operation, inputs, state);
    }
    activation.externalEffects.putIfAbsent(operation, () => {}).addAll(effects);
    var next = state.copy();
    if (memory case NativeResultMemory(:final type, :final arguments)) {
      final bytes = memoryLayout?.nativeLayout.of(type).size;
      next = next.overwriteNative(
        inputs.first,
        bytes == null
            ? FlowValue.unknown(.integer)
            : FlowValue.constant(Constant.integer(bytes)),
      );
      // The native implementation receives only its source arguments. In
      // particular a copied-out result does not retain its local destination.
      inputs = inputs.sublist(1);
      memory = arguments;
    }
    if (capturesArguments || accessesProgramState) {
      next.escape([
        if (capturesArguments) ...inputs,
        if (accessesProgramState) next.programValues,
      ]);
    }
    void invalidateAccessibleStorage() {
      final exposed = next.exposedValues;
      next.invalidate(
        [...inputs, exposed],
        globals: accessesProgramState,
        writtenReferences: nativeScalarCall
            ? next.exposedFrom([...inputs, exposed]).references
            : const FlowValue.bottom(),
      );
    }

    if (effects.contains(Effect.writesStorage)) {
      switch (memory) {
        case ArbitraryMemory():
          invalidateAccessibleStorage();
        case WrittenMemory(:final addressParameter, :final lengthParameter) ||
            ReleasedMemory(:final addressParameter, :final lengthParameter):
          next = next.overwriteNative(
            inputs[addressParameter],
            inputs[lengthParameter],
            release: memory is ReleasedMemory,
          );
        default:
          break;
      }
    }
    if (effects.contains(Effect.callsUserCode)) {
      // Re-entry follows values that crossed this boundary or declared exports.
      _admitEscaped(next, arguments: inputs);
      final merged = <_Activation>{};
      bool changed;
      do {
        changed = false;
        final current = nativeScalarCall ? next.copy() : next;
        for (final callback in {
          ..._escapingActivations,
          for (final target in _openEntries) _roots[target]!,
        }) {
          _ancestry.link(activation.body.target, callback.body.target);
          callback.readers.add(activation);
          _supply(
            callback,
            callback.arguments,
            current.project(callback.arguments),
          );
          if (!merged.add(callback)) continue;
          for (final exit in [callback.normal, callback.exceptional]) {
            if (exit != null) {
              changed = next.join(exit.project(const [])) || changed;
            }
          }
        }
        // A foreign invocation may write a pointer returned by one callback
        // before invoking a second callback. Callback summaries stay fixed
        // during this evaluation and notify this caller when they grow.
        if (nativeScalarCall &&
            changed &&
            effects.contains(Effect.writesStorage)) {
          invalidateAccessibleStorage();
        }
      } while (nativeScalarCall && changed);
    }
    final mapping = switch (memory) {
      ZeroedMemory(:final lengthParameter) => next.allocateMemory(
        FlowObject(operation, activation, type: resultType),
        inputs[lengthParameter],
        repeated:
            activation.repeated || _loopBlocks(activation.body).contains(block),
      ),
      _ => null,
    };
    return FlowResult(
      value:
          returned ??
          mapping?.value ??
          (resultType == .never
              ? const FlowValue.bottom()
              : FlowValue.unknown(resultType)
                    .join(next.exposedValues.check(resultType).value)
                    .withSources(const [])
                    .withReferences(inputs.map((value) => value.references))),
      normal: resultType == .never ? null : mapping?.normal ?? next,
      exceptional:
          effects.contains(Effect.mayThrow) ||
              effects.contains(Effect.allocates)
          ? next.copy()
          : null,
      allocationFailureOnly: !effects.contains(Effect.mayThrow),
    );
  }

  ({FlowValue value, bool proven}) _readTypeArgument(
    ReadFunctionTypeArgument operation,
    FlowValue function,
    FlowState state,
  ) {
    var result = const FlowValue.bottom(), proven = !function.isBottom;
    final visited = <FlowObject>{};
    void add(ValueType? type) {
      result = result.join(
        type == null || type.freeTypeParameters.isNotEmpty
            ? FlowValue.unknown(TypeMetadata.type)
            : FlowValue.constant(TypeConstant(type)),
      );
    }

    bool matchesOrigin(FlowValue value, [Set<FlowObject>? seen]) {
      if (value.isBottom ||
          value.unknownTypes.isNotEmpty ||
          value.addresses.isNotEmpty) {
        return false;
      }
      for (final constant in value.constants) {
        if (constant is! FunctionConstant ||
            (constant.invocationEntry ?? constant.target.implementation) !=
                operation.source) {
          return false;
        }
      }
      seen = {...?seen};
      for (final object in value.objects) {
        if (!seen.add(object)) return false;
        if (object.callableStorage case final storage?) {
          if (storage.origin != null) {
            final captures = state.capturesOf(object);
            if (captures == null || !matchesOrigin(captures.single, seen)) {
              return false;
            }
          } else if (!_provesStoredCallable(object, state, operation.source)) {
            return false;
          }
          continue;
        }
        if (object.site is InstantiateFunction ||
            object.site is InstantiateFunctionFrom) {
          final captures = state.capturesOf(object);
          if (captures == null || !matchesOrigin(captures.single, seen)) {
            return false;
          }
        } else {
          final sources = object.site is MakeClosure
              ? {(object.site as MakeClosure).target}
              : _creator(object).boundMethods[_original(object)] ??
                    const <FunctionTarget>{};
          if (sources.length != 1 || sources.single != operation.source) {
            return false;
          }
        }
      }
      return true;
    }

    void visit(FlowValue value) {
      if (value.unknownTypes.isNotEmpty || value.addresses.isNotEmpty) {
        proven = false;
        result = result.join(FlowValue.unknown(TypeMetadata.type));
      }
      for (final constant in value.constants) {
        if (constant is! FunctionConstant ||
            (constant.invocationEntry ?? constant.target.implementation) !=
                operation.source) {
          throw StateError('Callable type environment origin is not proven.');
        }
        final index = operation.source.typeParameters.indexOf(
          operation.parameter,
        );
        if (index >= 0) {
          if (constant.typeArguments == null) {
            throw StateError(
              'An uninstantiated function has no bound type argument.',
            );
          }
          add(constant.typeArguments![index]);
        } else {
          add(constant.ownerType?.typeEnvironment[operation.parameter]);
        }
      }
      for (final object in value.objects) {
        if (!visited.add(object)) continue;
        final captures = state.capturesOf(object);
        if (captures == null) {
          throw StateError('Callable environment has no storage.');
        }
        final own = operation.source.typeParameters.indexOf(
          operation.parameter,
        );
        if (object.callableStorage case final storage?) {
          if (storage.origin != null) {
            if (!matchesOrigin(captures.single)) {
              throw StateError(
                'Instantiated callable type environment origin is not proven.',
              );
            }
            if (own < 0) {
              visit(captures.single);
            } else {
              var list = state.storedFieldOf(object, storage.arguments);
              if (list == null) {
                throw StateError('Missing callable type arguments.');
              }
              for (var index = 0; index < own; index++) {
                list = _boundField(list!, TypeMetadata.tail, state);
              }
              result = result.join(
                _boundField(list!, TypeMetadata.head, state),
              );
            }
          } else {
            if (!_provesStoredCallable(object, state, operation.source)) {
              throw StateError(
                'Callable type environment origin is not proven.',
              );
            }
            final index = storage.parameters.indexOf(operation.parameter);
            if (index < 0) {
              throw StateError(
                'An uninstantiated function has no bound type argument.',
              );
            }
            final descriptor = state.storedFieldOf(
              object,
              storage.descriptors[index],
            );
            if (descriptor == null) {
              throw StateError('Missing captured type descriptor.');
            }
            result = result.join(descriptor);
          }
          continue;
        }
        if (object.site is InstantiateFunction ||
            object.site is InstantiateFunctionFrom) {
          if (!matchesOrigin(captures.single)) {
            throw StateError(
              'Instantiated callable type environment origin is not proven.',
            );
          }
          if (own >= 0) {
            add(_creator(object).instantiations[_original(object)]![own]);
          } else {
            visit(captures.single);
          }
          continue;
        }
        final sources = object.site is MakeClosure
            ? {(object.site as MakeClosure).target}
            : _creator(object).boundMethods[_original(object)] ??
                  const <FunctionTarget>{};
        if (sources.length != 1 || sources.single != operation.source) {
          throw StateError('Callable type environment origin is not proven.');
        }
        if (own >= 0) {
          throw StateError(
            'An uninstantiated function has no bound type argument.',
          );
        }
        if (object.site is MakeClosure) {
          add(_creator(object).executionEnvironment[operation.parameter]);
        } else {
          var found = false;
          for (final type in _receiverTypes(captures.single)) {
            final actual = type.asInstanceOf(operation.source.owner!);
            if (actual == null) continue;
            found = true;
            add(actual.typeEnvironment[operation.parameter]);
          }
          if (!found) add(null);
        }
      }
    }

    visit(function);
    return (value: result, proven: proven);
  }

  ({FlowValue value, bool proven}) _readEnvironment(
    ReadFunctionEnvironment operation,
    FlowValue function,
    FlowState state,
  ) {
    var result = const FlowValue.bottom(), proven = !function.isBottom;
    final visited = <FlowObject>{};
    void visit(FlowValue value) {
      if (value.unknownTypes.isNotEmpty || value.addresses.isNotEmpty) {
        proven = false;
        result = result.join(
          FlowValue.unknown(operation.type).withReferences([value.references]),
        );
      }
      if (value.constants.isNotEmpty) {
        throw StateError('A static function has no captured environment.');
      }
      for (final object in value.objects) {
        if (!visited.add(object)) continue;
        final captures = state.capturesOf(object);
        if (captures == null) {
          throw StateError('Callable environment has no capture storage.');
        }
        if (object.callableStorage case final storage?) {
          if (storage.origin != null) {
            visit(captures.single);
            continue;
          }
          if (!_provesStoredCallable(object, state, operation.source)) {
            throw StateError('Callable environment origin is not proven.');
          }
          result = result.join(
            operation.capture != null
                ? captures[operation.capture!]
                : operation.source.kind == .closure
                ? FlowValue.object(object)
                : captures.single,
          );
          continue;
        }
        if (object.site is InstantiateFunction ||
            object.site is InstantiateFunctionFrom) {
          visit(captures.single);
          continue;
        }
        final sources = object.site is MakeClosure
            ? {(object.site as MakeClosure).target}
            : _creator(object).boundMethods[_original(object)] ??
                  const <FunctionTarget>{};
        if (sources.length != 1 || sources.single != operation.source) {
          throw StateError('Callable environment origin is not proven.');
        }
        result = result.join(
          operation.capture != null
              ? captures[operation.capture!]
              : operation.source.kind == .closure
              ? FlowValue.object(object)
              : captures.single,
        );
      }
    }

    visit(function);
    return (value: result, proven: proven);
  }

  bool _provesStoredCallable(
    FlowObject object,
    FlowState state,
    FunctionTarget source,
  ) {
    final storage = object.callableStorage;
    if (storage == null || storage.source != source) return false;
    final table = state.storedFieldOf(object, storage.entries);
    return table != null &&
        table.addresses.isNotEmpty &&
        table.objects.isEmpty &&
        table.constants.isEmpty &&
        table.unknownTypes.isEmpty &&
        table.addresses.every(
          (address) => address.base == source && address.offset == 0,
        );
  }

  FlowValue _boundField(
    FlowValue receiver,
    InstanceField field,
    FlowState state,
  ) =>
      state.boundValueOf(
        LoadField(field, Block([field.owner]).parameters.single),
        [receiver],
      ) ??
      FlowValue.unknown(field.type);

  void _publishExternal(FlowState state) {
    final exposed = state.project(const []);
    final changed = _externalState == null
        ? true
        : _externalState!.join(exposed, widen: true);
    _externalState ??= exposed;
    if (!changed) return;
    for (final callback in {
      ..._escapingActivations,
      for (final target in _openEntries) _roots[target]!,
    }) {
      _supply(callback, callback.arguments, _externalState!);
    }
  }

  List<FlowValue>? _storedArguments(FlowObject object, FlowState state) {
    final storage = object.callableStorage!;
    var list = state.storedFieldOf(object, storage.arguments);
    final seen = <FlowValue>{};
    final values = <FlowValue>[];
    while (list != null && seen.add(list)) {
      if (list.constant case ScalarConstant(value: null)) return values;
      if (list.unknownTypes.isNotEmpty || list.constants.isNotEmpty ||
          list.objects.isEmpty) {
        return null;
      }
      values.add(_boundField(list, TypeMetadata.head, state));
      list = _boundField(list, TypeMetadata.tail, state);
    }
    return null;
  }

  void _admitEscaped(
    FlowState state, {
    Iterable<FlowValue> arguments = const [],
  }) {
    final reachable = state.exposedFrom([state.exposedValues, ...arguments]);
    _Activation? prepare(
      Object key,
      FunctionTarget target,
      Map<TypeParameterType, ValueType> environment,
    ) {
      final body = program.implementationOf(target);
      if (body is! IrFunction) return null;
      final activation = _escapedCalls.putIfAbsent(
        key,
        () => _Activation(body),
      );
      activation.repeated = true;
      _escapingActivations.add(activation);
      if (activation.mergeEnvironment(environment)) _pending.add(activation);
      return activation;
    }

    void admit(
      Object key,
      FunctionTarget target,
      List<FlowValue> arguments, {
      Map<TypeParameterType, ValueType> environment = const {},
      bool native = false,
    }) {
      final activation = prepare(key, target, environment);
      if (activation != null) {
        if (native) _nativeActivations.add(activation);
        _supply(activation, arguments, state.project(arguments));
      }
    }

    final visited = <(FlowObject, Object?, NativeCallbackTarget?)>{};
    final callbacks = <NativeCallbackTarget>{};
    void visit(
      FlowValue value, {
      List<ValueType> typeArguments = const [],
      Object? identity,
      NativeCallbackTarget? callback,
    }) {
      List<FlowValue> parameters(
        FunctionTarget target,
        Map<TypeParameterType, ValueType> environment,
      ) => callback == null
          ? [
              for (final type in target.signature.parameters)
                FlowValue.unknown(type.substituteForFlow(environment)),
            ]
          : target.signature.bind<FlowValue>(
              callback.dartSignature.parameters.map(FlowValue.unknown).toList(),
              const {},
              (index) => FlowValue.constant(
                program.implementationOf(target)!.defaults[index]!,
              ),
            );

      for (final address in value.addresses) {
        if (address.base case final NativeCallbackTarget definition) {
          if (!callbacks.add(definition)) continue;
          if (_nativeEntries[definition] case final entry?) {
            admit(
              definition,
              entry,
              entry.parameterTypes.map(FlowValue.unknown).toList(),
              native: true,
            );
            continue;
          }
        }
        switch (address.base) {
          case final StaticCallbackTarget definition:
            final target = definition.function;
            final args = target.signature.bind<FlowValue>(
              definition.dartSignature.parameters
                  .map(FlowValue.unknown)
                  .toList(),
              const {},
              (index) => FlowValue.constant(
                program.implementationOf(target)!.defaults[index]!,
              ),
            );
            admit(definition, target, args, native: true);
          case final ClosureCallbackTarget definition:
            final lookup = prepare(
              (definition, 'lookup'),
              definition.lookup,
              const {},
            );
            if (lookup == null) continue;
            _nativeLookups.add(lookup);
            _supply(lookup, [
              FlowValue.unknown(.integer),
            ], state.project(const []));
            if (lookup.normal case final normal?) {
              state.join(normal.project([lookup.returned]));
              visit(
                lookup.returned,
                identity: definition,
                callback: definition,
              );
            }
        }
      }

      for (final constant in value.constants.whereType<FunctionConstant>()) {
        final (:target, :owner, typeArguments: applied) = constant
            .resolveInvocation(
              typeArguments.isEmpty
                  ? (constant.type as FunctionType).typeParameters
                  : typeArguments,
            );
        final environment = {
          if (owner != null) ...target.environmentFor(owner),
          for (final (i, type) in applied.indexed)
            target.typeParameters[i]: type,
        };
        final key = callback == null
            ? identity ?? constant.structuralKey
            : (identity, constant.structuralKey);
        final arguments = parameters(target, environment);
        if (target.kind != .initializer) {
          admit(
            key,
            target,
            arguments,
            environment: environment,
            native: callback != null,
          );
          continue;
        }
        final activation = prepare(key, target, environment);
        if (activation == null) continue;
        final receiver = _constructedReturns.putIfAbsent(
          activation,
          () => FlowValue.object(
            FlowObject(
              Construct(
                target,
                blockParameters(target.signatureFor(owner!).parameters),
                instantiatedType: owner,
              ),
              activation,
            ),
          ),
        );
        state.construct(
          receiver.objects.single,
          target,
          arguments,
          repeated: true,
          invoke: (_, arguments, input) {
            _supply(activation, arguments, input.project(arguments));
            return _unreachable;
          },
        );
      }
      for (final object in value.objects) {
        if (!visited.add((object, _typeKey(typeArguments), callback))) continue;
        final captures = state.capturesOf(object);
        if (captures == null) continue;
        if (object.callableStorage case final storage?) {
          if (storage.source case final target?) {
            if (!_provesStoredCallable(object, state, target)) continue;
            final environment = <TypeParameterType, ValueType>{
              for (final (index, parameter) in storage.parameters.indexed)
                parameter: switch (state.storedFieldOf(object,
                    storage.descriptors[index])?.constant) {
                  TypeConstant(:final representedType) => representedType,
                  _ => parameter,
                },
              for (final (index, parameter) in target.typeParameters.indexed)
                parameter: index < typeArguments.length
                    ? typeArguments[index] : parameter,
            };
            admit(callback == null ? identity ?? object : (identity, object),
                target, [
                  if (target.kind == .closure) FlowValue.object(object),
                  ...captures,
                  ...parameters(target, environment),
                ], environment: environment, native: callback != null);
          } else {
            // These are the actual descriptor fields produced by the checked
            // runtime instantiation. Unknown descriptors keep their own binder
            // symbolic when the original source is admitted below.
            final types = <ValueType>[];
            var list = state.storedFieldOf(object, storage.arguments);
            final seen = <FlowValue>{};
            while (list != null && seen.add(list) &&
                list.constant is! ScalarConstant) {
              final head = _boundField(list, TypeMetadata.head, state);
              if (head.constant case TypeConstant(:final representedType)) {
                types.add(representedType);
              } else {
                types.clear();
                break;
              }
              list = _boundField(list, TypeMetadata.tail, state);
            }
            visit(captures.single, typeArguments: types,
                identity: identity ?? object, callback: callback);
          }
          continue;
        }
        final creator = _creator(object);
        if (creator.instantiations[_original(object)] case final arguments?) {
          visit(
            captures.single,
            typeArguments: arguments,
            identity: identity ?? object,
            callback: callback,
          );
          continue;
        }
        if (object.site case MakeClosure(:final target)) {
          final environment = {
            ...creator.executionEnvironment,
            for (final (i, type) in typeArguments.indexed)
              target.typeParameters[i]: type,
          };
          admit(
            callback == null ? identity ?? object : (identity, object),
            target,
            [
              FlowValue.object(object),
              ...captures,
              ...parameters(target, environment),
            ],
            environment: environment,
            native: callback != null,
          );
        } else {
          for (final target
              in creator.boundMethods[_original(object)] ??
                  <FunctionTarget>{}) {
            for (final type in _receiverTypes(captures.single)) {
              if (type.asInstanceOf(target.owner!) == null) continue;
              final environment = {
                ...target.environmentFor(type),
                for (final (i, argument) in typeArguments.indexed)
                  target.typeParameters[i]: argument,
              };
              admit(
                (identity ?? object, target, type),
                target,
                [
                  _receiverValue(captures.single, type),
                  ...parameters(target, environment),
                ],
                environment: environment,
                native: callback != null,
              );
            }
          }
        }
      }
    }

    visit(reachable);
  }

  FlowValue _receiverValue(FlowValue value, ClassType type) {
    return value.forReceiverClass(type);
  }

  Iterable<ClassType> _receiverTypes(FlowValue value) sync* {
    final seen = <ClassType>{};
    for (final type in [
      ...value.constants.map((constant) => constant.provenValueType),
      ...value.objects.map((object) => object.type),
      ...value.addresses.map((address) => address.type),
    ]) {
      final nominal = type == .nullType
          ? ValueType.nullClass
          : type is FunctionType
          ? ValueType.function
          : type;
      if (nominal is ClassType && seen.add(nominal)) yield nominal;
    }
    for (final bound in value.unknownTypes) {
      bool allowed(ClassType type) =>
          value.unknownReceiverClasses?.contains(type.declaration) ?? true;
      if (bound.mayBeNull &&
          allowed(ValueType.nullClass) &&
          seen.add(ValueType.nullClass)) {
        yield ValueType.nullClass;
      }
      if (bound.nonNullable is FunctionType ||
          bound.nonNullable == ValueType.function) {
        if (allowed(ValueType.function) && seen.add(ValueType.function)) {
          yield ValueType.function;
        }
        continue;
      }
      const primitiveTypes = <ClassType>[
        ValueType.integer,
        ValueType.floating,
        ValueType.boolean,
        ValueType.string,
      ];
      for (final type in _receiverBounds.putIfAbsent(
        bound,
        () => [
          for (final type in primitiveTypes)
            if (bound.mayHaveInstance(type)) type,
          if (!primitiveTypes.contains(bound.nonNullable))
            for (final declaration in program.classes)
              if (!declaration.type.isAbstract &&
                  bound.mayHaveInstance(declaration.type))
                declaration.type,
        ],
      )) {
        if (allowed(type) && seen.add(type)) yield type;
      }
    }
  }

  Set<Block> _loopBlocks(IrCallable body) => body is! IrFunction
      ? const {}
      : _cyclic.putIfAbsent(body.target, () => cyclicBlocks(body.blocks));
}

bool _deferredAllocationProjection(Instruction operation) =>
    operation.implicitMember != null || switch (operation) {
  DirectCall() || InstanceCall() || FunctionCall() || DynamicDispatch() ||
  InitializeObject() || LoadGlobal() || LoadField() || ReadCell() ||
  CheckedTypeArgument(implementation: != null) => true,
  _ => false,
};

/// Immutable queries over the converged activations of one graph.
final class ProgramFlowFacts._(final ProgramFlow _flow)
    implements ProgramCallFacts {
  /// The exact verified graph used to establish these facts.
  @override
  final IrProgram program = _flow.program;

  /// Actual invocations, without promoting retained bodies to roots.
  List<FlowEntry> get entries {
    _check();
    return List.unmodifiable(_flow._entries);
  }

  /// Independently entered declarations.
  Set<FunctionTarget> get roots {
    _check();
    return Set.unmodifiable(_flow._roots.keys);
  }

  /// Bodies whose exceptional completion can reach a caller outside this graph.
  Set<FunctionTarget> get escapingThrows {
    _check();
    return Set.unmodifiable({
      ..._flow._roots.keys,
      for (final activation in _flow._escapingActivations)
        activation.body.target,
    });
  }

  /// Entries whose callers admit the full declared argument bounds.
  Set<FunctionTarget> get openEntries {
    _check();
    return Set.unmodifiable(_flow._openEntries);
  }

  @override
  bool coversEntry(FunctionTarget target) {
    _check();
    target = target.implementation;
    if (!_flow._definitions.contains(target)) return false;
    return [
      ?_flow._roots[target],
      for (final activation in _flow._escapingActivations)
        if (activation.body.target == target &&
            !_flow._nativeLookups.contains(activation))
          activation,
    ].any(
      (activation) => activation.arguments.indexed.every((entry) {
        final actual = entry.$2.withSources(const []);
        return actual.join(
              FlowValue.unknown(
                target.parameterTypes[entry.$1],
                external: actual.externalUnknownTypes.contains(
                  target.parameterTypes[entry.$1],
                ),
              ),
            ) ==
            actual;
      }),
    );
  }

  @override
  bool allows(Value receiver, ClassType actual) {
    _check();
    // New representation helpers have no execution facts yet. The explicit
    // structural-consumer fallback is a static bound, never a solved input.
    if (!owns(receiver)) return receiver.unviewedType.mayHaveInstance(actual);
    return valueOf(receiver).mayHaveInstance(actual);
  }

  /// Nominal receivers admitted by actual source value facts in this graph.
  ///
  /// Unreached values contribute no classes. This query creates neither entry
  /// roots nor executable targets; unresolved receiver bounds remain broad.
  Set<ClassType> receiverClassesOf(Value receiver) {
    _check();
    return Set.unmodifiable(_flow._receiverTypes(valueOf(receiver)));
  }

  @override
  Set<FunctionTarget> executionTargetsOf(Instruction operation) =>
      targetsOf(operation);

  /// Whether every reached execution has the allocation's invariant slot view.
  bool provesStorageView(Instruction operation) {
    _check();
    final reached = _activations.where((a) => a.before.containsKey(operation));
    return reached.isNotEmpty && reached.every((a) => a.storageViews[operation] == true);
  }

  /// Whether every actual input proves the environment's source identity.
  bool provesFunctionEnvironment(Instruction operation) {
    _check();
    final reached = _activations
        .where((activation) => activation.before.containsKey(operation))
        .toList();
    return reached.isNotEmpty &&
        reached.every(
          (activation) => activation.environmentReads[operation] == true,
        );
  }

  /// Entry returns visible to an unknown outside consumer.
  Set<FunctionTarget> get escapingReturns {
    _check();
    return Set.unmodifiable(_flow._escapingReturns);
  }

  /// Bodies and imports reached by executable calls.
  @override
  Set<FunctionTarget> get definitions {
    _check();
    return Set.unmodifiable(_flow._definitions);
  }

  /// Known source calls whose actual execution entry still needs realization.
  ///
  /// Their semantic bodies have been analyzed with their real inputs. This is
  /// a lowering obligation, never permission to emit the source as an adapter
  /// or to retain an arbitrary target as an additional root.
  Map<Instruction, Set<FunctionTarget>> get pendingExecutionCalls {
    _check();
    final pending = <Instruction, Set<FunctionTarget>>{};
    for (final activation in _activations) {
      for (final entry in activation.pendingExecution.entries) {
        (pending[entry.key] ??= {}).addAll(entry.value);
      }
    }
    return Map.unmodifiable({
      for (final entry in pending.entries)
        entry.key: Set<FunctionTarget>.unmodifiable(entry.value),
    });
  }

  /// Verifies graph identity and rejects facts invalidated by new inputs.
  @override
  void checkProgram(IrProgram program) {
    _check();
    if (!identical(this.program, program)) {
      throw ArgumentError('Program facts belong to another graph.');
    }
  }

  void _check() {
    if (!identical(_flow._facts, this)) {
      throw StateError('Program facts were invalidated by new invocations.');
    }
  }

  Iterable<_Activation> get _activations => _flow._activeContexts;

  /// Opaque activation identities for context-specific queries.
  Iterable<Object> activationsOf(FunctionTarget target) {
    _check();
    return List.unmodifiable(
      _activations.where((a) => a.body.target == target.implementation),
    );
  }

  /// Callee executions reached by [operation] in the selected caller inputs.
  Set<Object> callActivationsOf(Instruction operation, {Object? activation}) =>
      Set.unmodifiable({
        for (final caller in _at(operation, activation))
          ...?caller.calls[operation],
      });

  Iterable<_Activation> _at(Object source, Object? activation) {
    _check();
    final target = _flow._owners[source];
    if (target == null) {
      throw ArgumentError(
        'Query requires a source-owned value, block or edge.',
      );
    }
    if (activation == null) {
      return _activations.where((a) => a.body.target == target);
    }
    if (activation is! _Activation ||
        !_activations.contains(activation) ||
        activation.body.target != target) {
      throw ArgumentError('Activation does not own this source operation.');
    }
    return [activation];
  }

  /// Whether a summary allocation is the other allocation's renamed instance.
  /// Sibling call instances stay distinct; this relation only serves cross-body demand.
  bool mayAliasAcrossSummaries(FlowObject left, FlowObject right) {
    _check();
    return _mayAliasAcrossSummaries(left, right);
  }

  /// Whether a value is queryable in this graph, including graph-independent constants.
  bool owns(Value value) {
    _check();
    return value is Constant ||
        _flow._owners.containsKey(value is TestedValue ? value.test : value);
  }

  /// Independent point snapshots, including paths with no eventual return.
  ({FlowState before, FlowState? normal, FlowState? exceptional})? pointStateOf(
    Instruction operation, {
    Object? activation,
  }) {
    FlowState? before, normal, exceptional;
    for (final item in _at(operation, activation)) {
      if (item.before[operation] case final state?) {
        before = before == null ? state.copy() : (before..join(state));
      }
      if (item.after[operation] case final state?) {
        normal = normal == null ? state.copy() : (normal..join(state));
      }
      if (item.thrown[operation] case final state?) {
        exceptional = exceptional == null
            ? state.copy()
            : (exceptional..join(state));
      }
    }
    return before == null
        ? null
        : (before: before, normal: normal, exceptional: exceptional);
  }

  /// Values across all executable activations unless one is specified.
  FlowValue valueOf(Value value, {Object? activation}) {
    _check();
    if (value is Constant) return FlowValue.constant(value);
    if (value is CallFrameValue) return FlowValue.unknown(value.type);
    if (value is TestedValue) {
      var result = const FlowValue.bottom();
      for (final item in _at(value.test, activation)) {
        final condition = item.values[value.test];
        if (condition == null || condition.isBottom) continue;
        if (condition.constant case ScalarConstant(value: final bool outcome)
            when outcome != value.outcome) {
          continue;
        }
        result = result.join(
          valueOf(value.test.operand, activation: item)
              .check(
                value.test.testedType.substituteForFlow(
                  item.executionEnvironment,
                ),
                negated: value.outcome == value.test.negated,
                runtimeTypes: true,
              )
              .value,
        );
      }
      return result;
    }
    var result = const FlowValue.bottom();
    for (final item in _at(value, activation)) {
      result = result.join(item.values[value] ?? const FlowValue.bottom());
    }
    return result;
  }

  /// Same-function SSA aliases valid in every reached selected activation.
  Set<Value> equivalentsOf(Value value, {Object? activation}) {
    _check();
    if (value is Constant) return Set.unmodifiable({value});
    if (value is TestedValue) {
      Set<Value>? common;
      for (final item in _at(value.test, activation)) {
        if (valueOf(value, activation: item).isBottom) continue;
        final local = equivalentsOf(value.test.operand, activation: item);
        common = common == null ? local : common.intersection(local);
      }
      return Set.unmodifiable(common ?? const <Value>{});
    }
    Set<Value>? common;
    for (final item in _at(value, activation)) {
      final fact = item.values[value];
      if (fact == null || fact.isBottom) continue;
      final local = {
        for (final source in fact.sources)
          if (identical(source.activation, item) &&
              _flow._owners[source.value] == item.body.target)
            source.value,
      };
      common = common == null ? local : common.intersection(local);
    }
    return Set.unmodifiable(common ?? const <Value>{});
  }

  /// Whether evaluation actually reaches this operation, including call tails.
  bool reachesOperation(Instruction operation, {Object? activation}) => _at(
    operation,
    activation,
  ).any((item) => item.before.containsKey(operation));

  /// Storage carried by this executable CFG edge, before its parameters bind.
  FlowState? edgeStateOf(Jump edge, {Object? activation}) {
    FlowState? result;
    for (final item in _at(edge, activation)) {
      if (item.edgeStates[edge] case final state?) {
        result = result == null ? state.copy() : (result..join(state));
      }
    }
    return result;
  }

  /// Whether a block is reached in the selected activation set.
  bool reachesBlock(Block block, {Object? activation}) =>
      _at(block, activation).any((item) => item.blocks.contains(block));

  /// Whether an edge participates in the selected executable paths.
  bool reachesEdge(Jump edge, {Object? activation}) =>
      _at(edge, activation).any((item) => item.edges.contains(edge));

  /// Actual executable targets; unknown alternatives are reported separately.
  Set<FunctionTarget> targetsOf(Instruction operation, {Object? activation}) =>
      Set.unmodifiable(
        _at(
          operation,
          activation,
        ).expand((item) => item.targets[operation] ?? const <FunctionTarget>{}),
      );

  /// Language callable implementations before an explicit execution binding.
  ///
  /// Use [targetsOf] for semantic rewrites: adapters can have observable effects.
  Set<FunctionTarget> sourceTargetsOf(Instruction operation) {
    _check();
    return Set.unmodifiable({
      for (final activation in _activations)
        ...?activation.callableSources[operation],
    });
  }

  /// Bodies whose exceptions can leave this operation, including allocation
  /// failure reporting that has no explicit source call.
  Set<FunctionTarget> unwindingTargetsOf(Instruction operation) => {
    for (final caller in _at(operation, null))
      for (final site in [operation, ?caller.allocationCalls[operation]])
        for (final callee in caller.calls[site] ?? <_Activation>{})
          if (callee.exceptional != null) callee.body.target,
  };

  /// Whether a reached invocation still has an unresolved callable alternative.
  bool hasUnknownCall(Instruction operation, {Object? activation}) => _at(
    operation,
    activation,
  ).any((item) => item.unknownCalls.contains(operation));

  /// Possible normal and exceptional exits, not a termination proof.
  ({bool normal, bool exceptional}) exitsOf(
    Instruction operation, {
    Object? activation,
  }) {
    var normal = false;
    var exceptional = false;
    for (final item in _at(operation, activation)) {
      normal |= item.exits[operation]?.normal ?? false;
      exceptional |= item.exits[operation]?.exceptional ?? false;
    }
    return (normal: normal, exceptional: exceptional);
  }

  /// Actual exception values on this operation's exceptional exit.
  ({FlowValue exception, FlowValue stackTrace}) failureOf(
    Instruction operation, {
    Object? activation,
  }) {
    var exception = const FlowValue.bottom();
    var trace = const FlowValue.bottom();
    for (final item in _at(operation, activation)) {
      exception = exception.join(
        item.exceptions[operation] ?? const FlowValue.bottom(),
      );
      trace = trace.join(item.traces[operation] ?? const FlowValue.bottom());
    }
    return (exception: exception, stackTrace: trace);
  }

  /// Effects of reached operations and their analyzed callees.
  Set<Effect> effectsOf(Instruction operation, {Object? activation}) =>
      Set.unmodifiable({
        for (final item in _at(operation, activation)) ...[
          ...?item.operationEffects[operation],
          ...?item.externalEffects[operation],
          for (final call in [operation, ?item.allocationCalls[operation]])
            for (final callee in item.calls[call] ?? <_Activation>{})
              ...callee.effects,
        ],
      });

  /// Whether discarding an unused operation preserves effects and termination.
  bool canDiscard(Instruction operation, {Object? activation}) {
    final exits = exitsOf(operation, activation: activation);
    if (!exits.normal) return false;
    for (final item in _at(operation, activation)) {
      if (item.semanticFailures.contains(operation)) return false;
      if (!_discardableOperation(item, operation, {})) return false;
    }
    return true;
  }

  bool _discardableOperation(
    _Activation activation,
    Instruction operation,
    Set<_Activation> visiting, {
    bool ignoreFailure = false,
    bool stableInitialization = false,
  }) {
    if (activation.unknownCalls.contains(operation)) return false;
    if (activation.externalCalls.contains(operation)) {
      final targets = activation.targets[operation] ?? const {};
      if (targets.isEmpty ||
          targets.any(
            (target) => switch (_flow.program.implementationOf(target)) {
              IrExternal(terminates: true) || IrFunction() => false,
              _ => true,
            },
          )) {
        return false;
      }
    }
    final callees = activation.calls[operation] ?? const <_Activation>{};
    var localAddress = false;
    if (stableInitialization && operation is ReferenceAddress) {
      final value = operation.object is Constant
          ? FlowValue.constant(operation.object as Constant)
          : activation.values[operation.object];
      localAddress =
          value != null &&
          !value.isBottom &&
          value.unknownTypes.isEmpty &&
          value.addresses.isEmpty &&
          value.objects.every(
            (object) => !activation.incomingIdentities.contains(object),
          );
    }
    // Pure initialization may wait until a later read, even for writable storage.
    final binding =
        operation is LoadGlobal &&
        operation.global.initializer != null &&
        callees.isNotEmpty &&
        callees.every(
          (callee) =>
              callee.body.target ==
                  operation.global.initializer!.implementation &&
              _discardableBody(callee, visiting, stableInitialization: true),
        );
    for (final effect in {
      ...?activation.operationEffects[operation],
      ...?activation.externalEffects[operation],
    }) {
      if (stableInitialization &&
          effect == .readsStorage &&
          !(operation is LoadGlobal && operation.global.isFinal) &&
          !localAddress) {
        return false;
      }
      if (effect != .readsStorage &&
          effect != .allocates &&
          effect != .mayThrow &&
          !(effect == .writesStorage && binding)) {
        return false;
      }
    }
    for (final callee in callees) {
      if (!_discardableBody(
        callee,
        visiting,
        ignoreFailure: ignoreFailure,
        stableInitialization: stableInitialization,
      )) {
        return false;
      }
    }
    final failure = activation.allocationCalls[operation];
    return failure == null ||
        _discardableOperation(
          activation,
          failure,
          visiting,
          ignoreFailure: true,
          stableInitialization: stableInitialization,
        );
  }

  bool _discardableBody(
    _Activation activation,
    Set<_Activation> visiting, {
    bool ignoreFailure = false,
    bool stableInitialization = false,
  }) {
    if (!visiting.add(activation) ||
        activation.recursive ||
        activation.body is! IrFunction ||
        (activation.normal == null &&
            !(ignoreFailure && activation.exceptional != null)) ||
        (!ignoreFailure && activation.hasSemanticFailure)) {
      return false;
    }
    final body = activation.body as IrFunction;
    if (body.bodyKind != .synchronous ||
        cyclicBlocks(body.blocks, edges: activation.edges).isNotEmpty ||
        activation.unknownCalls.isNotEmpty) {
      return false;
    }
    for (final operation in {
      ...activation.operationEffects.keys,
      ...activation.externalEffects.keys,
      ...activation.calls.keys,
    }) {
      if (activation.allocationCalls.containsValue(operation)) continue;
      if (!_discardableOperation(
        activation,
        operation,
        visiting,
        ignoreFailure: ignoreFailure,
        stableInitialization: stableInitialization,
      )) {
        return false;
      }
    }
    visiting.remove(activation);
    return true;
  }

  /// Exceptions that leave the selected body executions.
  ({FlowValue exception, FlowValue stackTrace}) thrownBy(
    FunctionTarget target, {
    Object? activation,
  }) {
    _check();
    var exception = const FlowValue.bottom();
    var trace = const FlowValue.bottom();
    for (final item in _activations.where(
      (a) => a.body.target == target.implementation,
    )) {
      if (activation == null || identical(activation, item)) {
        exception = exception.join(item.exception);
        trace = trace.join(item.stackTrace);
      }
    }
    return (exception: exception, stackTrace: trace);
  }

  /// Returned values from the selected executions of a callable.
  FlowValue returnedBy(FunctionTarget target, {Object? activation}) {
    _check();
    var result = const FlowValue.bottom();
    for (final item in _activations.where(
      (a) => a.body.target == target.implementation,
    )) {
      if (activation == null || identical(activation, item)) {
        result = result.join(item.returned);
      }
    }
    return result;
  }
}

final class _ContextKey(
  final FunctionTarget target,
  List<FlowValue> arguments,
  Map<TypeParameterType, ValueType> environment,
  final Object state,
  final bool repeated,
  final Object? aliases,
) {
  final List<FlowValue> arguments = .unmodifiable(arguments);
  final Map<TypeParameterType, ValueType> environment = Map.unmodifiable(
    _completeEnvironment(target, environment),
  );
  @override
  bool operator ==(Object other) =>
      other is _ContextKey &&
      target == other.target &&
      repeated == other.repeated &&
      state == other.state &&
      aliases == other.aliases &&
      _sameValues(arguments, other.arguments) &&
      environment.length == other.environment.length &&
      environment.entries.every(
        (entry) => other.environment[entry.key] == entry.value,
      );
  @override
  int get hashCode => Object.hash(
    target,
    Object.hashAll(arguments),
    state,
    repeated,
    aliases,
    Object.hashAllUnordered(
      environment.entries.map((entry) => (entry.key, entry.value)),
    ),
  );
}

final class _AccessPlan(IrFunction body) {
  final parameters = <BlockParameter, Block>{};
  final incoming = <Block, List<Jump>>{};
  bool bindsContext = false;

  this {
    for (final block in body.blocks) {
      bindsContext |=
          block.instructions.any(
            (operation) => operation is BindNativeContext,
          ) ||
          block.end is Invoke &&
              (block.end as Invoke).operation is BindNativeContext;
      for (final parameter in block.parameters) {
        parameters[parameter] = block;
      }
      for (final edge in block.successors) {
        (incoming[edge.target] ??= []).add(edge);
      }
    }
  }
}

/// Transitive reachability between the actual functions discovered in one
/// graph. It rules out impossible recursion before traversing activations.
/// Retiring a call can leave a candidate path here; the activation walk still
/// proves the concrete cycle, including callback identity, before any join.
final class _CallAncestry {
  final _parents = <FunctionTarget, Set<FunctionTarget>>{};
  final _descendants = <FunctionTarget, Set<FunctionTarget>>{};

  bool mayHaveAncestor(FunctionTarget child, FunctionTarget ancestor) =>
      child == ancestor || (_parents[child]?.contains(ancestor) ?? false);

  void link(FunctionTarget parent, FunctionTarget child) {
    if (_parents[child]?.contains(parent) ?? false) return;
    final upstream = {parent, ...?_parents[parent]};
    final downstream = {child, ...?_descendants[child]};
    for (final target in downstream) {
      (_parents[target] ??= {}).addAll(upstream);
    }
    for (final source in upstream) {
      (_descendants[source] ??= {}).addAll(downstream);
    }
  }
}

final class _CallSite(
  final _Activation caller,
  final Instruction operation,
  final FunctionTarget target,
) {
  final contexts = <_ContextKey, _CallInput>{};
  final joined = <_ContextKey>{};
  final allocations = <Object, FlowObject>{};
  bool recursive = false;
}

/// A call site's joined input, independent of other users of a shared summary.
final class _CallInput(List<FlowValue> arguments, FlowState input) {
  final List<FlowValue> arguments = List.of(arguments);
  final FlowState state = input.copy(resetWrites: true);
  final _normalized = <FlowObject, FlowObject>{};
  final originals = <FlowObject, FlowObject>{};
  Set<FlowObject>? _incoming;
  Set<FlowObject> get incomingIdentities =>
      _incoming ??= state.allocationIdentities(arguments);
  ({List<FlowValue> arguments, FlowState state})? _prepared;
  bool _private = true;
  int _nextIdentity = 0;
  _Activation? activation;

  void join(List<FlowValue> incoming, FlowState input) {
    var changed = false;
    for (final (index, value) in incoming.indexed) {
      final joined = arguments[index].join(value);
      changed |= joined != arguments[index];
      arguments[index] = joined;
    }
    changed = state.join(input.copy(resetWrites: true)) || changed;
    if (changed) {
      _incoming = null;
      _prepared = null;
    }
  }

  ({List<FlowValue> arguments, FlowState state, bool reset}) prepare(
    FunctionTarget target,
    Map<(FunctionTarget, int), _InputIdentity> identities, {
    required bool private,
  }) {
    if (!_private) return (arguments: arguments, state: state, reset: false);
    if (_prepared case final ready? when private) {
      return (arguments: ready.arguments, state: ready.state, reset: false);
    }
    final anchors = state.anchoredIdentities();
    final reset =
        _private &&
        (!private || _normalized.keys.any(anchors.contains)) &&
        _normalized.isNotEmpty;
    if (!private || reset) {
      _private = false;
      _normalized.clear();
      originals.clear();
      _prepared = null;
    }
    if (!_private) return (arguments: arguments, state: state, reset: reset);
    final positions = <FlowObject, int>{};
    for (final (index, argument) in arguments.indexed) {
      for (final object in [
        ...argument.objects,
        for (final address in argument.addresses)
          if (address.base case final FlowObject object)
            object
          else if (address.base case FlowRegion(:final allocation))
            allocation,
      ]) {
        positions.putIfAbsent(object, () => index);
      }
    }
    final objects =
        incomingIdentities
            .where(
              (object) =>
                  !anchors.contains(object) && !_normalized.containsKey(object),
            )
            .toList()
          ..sort((left, right) {
            var order = (positions[left] ?? arguments.length).compareTo(
              positions[right] ?? arguments.length,
            );
            if (order == 0) {
              order = identityHashCode(left.site)
                  .compareTo(identityHashCode(right.site));
            }
            if (order == 0) {
              order = left.type.hashCode.compareTo(right.type.hashCode);
            }
            if (order == 0) {
              order = (left.variant?.hashCode ?? 0).compareTo(
                right.variant?.hashCode ?? 0,
              );
            }
            return order == 0 ? left.hashCode.compareTo(right.hashCode) : order;
          });
    final reserved = {...incomingIdentities, ...originals.keys, ...anchors};
    for (final object in objects) {
      FlowObject renamed;
      do {
        final index = _nextIdentity++;
        renamed = FlowObject(
          object.site,
          identities.putIfAbsent((
            target,
            index,
          ), () => _InputIdentity(target, index)),
          type: object.type,
          variant: object.variant,
          cellStorage: object.cellStorage,
          storageView: object.storageView,
        );
      } while (reserved.contains(renamed));
      reserved.add(renamed);
      _normalized[object] = renamed;
      originals[renamed] = object;
      (renamed.activation as _InputIdentity).origins
          .putIfAbsent(renamed, () => {})
          .add(object);
    }
    final ready = (
      arguments: [
        for (final value in arguments)
          value.mapObjects((object) => _normalized[object] ?? object),
      ],
      state: state.mapObjects(_normalized),
    );
    _prepared = ready;
    return (arguments: ready.arguments, state: ready.state, reset: false);
  }
}

/// One formal allocation identity; the original instruction and type remain intact.
final class _InputIdentity(final FunctionTarget target, final int index) {
  // Demand can cross a shared input boundary in either direction. Keep each
  // exact binding; sharing a formal never identifies its different callers.
  final origins = <FlowObject, Set<FlowObject>>{};
}

final class _AllocationContext(
  final FlowObject original,
  final _CallSite site,
) {
  final Set<FlowObject> origins = {original};
}

// A call-site's new allocation survives a change of summary precision. Nested
// source calls remain distinct; callable capabilities retain their creator.
Object _allocationKey(FlowObject object) {
  if (object.type is FunctionType || object.variant != null) return object;
  final origin = switch (object.activation) {
    _Activation(:final body) => body.target,
    _AllocationContext(:final original, :final site) => (
      _allocationKey(original),
      site.operation,
      site.target,
    ),
    final identity => identity,
  };
  return (object.site, object.type, object.variant, object.storageView, origin);
}

FlowObject _original(FlowObject object) {
  while (object.activation is _AllocationContext) {
    object = (object.activation as _AllocationContext).original;
  }
  return object;
}

_Activation _creator(FlowObject object) =>
    _original(object).activation as _Activation;

bool _mayAliasAcrossSummaries(FlowObject left, FlowObject right) {
  final visited = <(FlowObject, FlowObject)>{};

  bool descendsFrom(FlowObject value, FlowObject ancestor) {
    final pending = [value], seen = <FlowObject>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current == ancestor) return true;
      if (!seen.add(current)) continue;
      if (current.activation case _AllocationContext(:final origins)) {
        pending.addAll(origins);
      }
    }
    return false;
  }

  Iterable<FlowObject> inputOrigins(FlowObject value) sync* {
    final pending = [value], seen = <FlowObject>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!seen.add(current)) continue;
      switch (current.activation) {
        case _InputIdentity(:final origins):
          yield* origins[current] ?? const <FlowObject>{};
        case _AllocationContext(:final origins):
          pending.addAll(origins);
        default:
          break;
      }
    }
  }

  bool overlaps(FlowObject a, FlowObject b) {
    if (!visited.add((a, b))) return false;
    if (descendsFrom(a, b) || descendsFrom(b, a)) return true;
    return inputOrigins(a).any((origin) => overlaps(origin, b)) ||
        inputOrigins(b).any((origin) => overlaps(a, origin));
  }

  return overlaps(left, right);
}

bool _equivalent(FlowValue left, FlowValue right) =>
    left.sources.any(right.sources.contains) ||
    (left.constant != null &&
        right.constant != null &&
        left.constant!.structuralKey == right.constant!.structuralKey);

Set<Object>? _callableOrigins(FlowValue value) {
  if (value.unknownTypes.isNotEmpty || value.addresses.isNotEmpty) return null;
  final origins = <Object>{};
  for (final constant in value.constants) {
    if (constant is! FunctionConstant) return null;
    origins.add(constant.invocationEntry ?? constant.target.implementation);
  }
  for (final object in value.objects) {
    if (object.type is! FunctionType) return null;
    origins.add(switch (object.site) {
      MakeClosure(:final target) => target,
      final site => site,
    });
  }
  return origins.isEmpty ? null : origins;
}

final class _StateSummary(FlowState before, FlowState after) {
  final FlowState entry = before.copy();
  final FlowState exit = after.copy();

  bool join(FlowState before, FlowState after, {required bool widen}) {
    final changed = entry.join(before, widen: widen);
    return exit.join(after, widen: widen) || changed;
  }
}

final class _Activation(final IrCallable body) {
  _ContextKey? inputKey;
  // Caller-owned identities are stable across applications of this input
  // version. _supply invalidates the closure whenever arguments or state grow.
  Set<FlowObject>? _incomingIdentities;
  Set<FlowObject> get incomingIdentities =>
      _incomingIdentities ??= input!.allocationIdentities(arguments);
  bool shareInput = true;
  late final dominance = ValueDominance(body as IrFunction);
  late final Set<Jump> backEdges = switch (body) {
    IrFunction(:final entry) => _backEdges(entry),
    _ => {},
  };
  final List<FlowValue> arguments = [
    for (final _ in body.target.parameterTypes) const FlowValue.bottom(),
  ];
  final values = <Value, FlowValue>{};
  final environmentReads = <Instruction, bool>{};
  final storageViews = <Instruction, bool>{};
  final edgeStates = <Jump, FlowState>{};
  final before = <Instruction, FlowState>{};
  final after = <Instruction, FlowState>{};
  final thrown = <Instruction, FlowState>{};
  final exceptions = <Instruction, FlowValue>{};
  final semanticFailures = <Instruction>{};
  final traces = <Instruction, FlowValue>{};
  final blocks = <Block>{};
  final edges = <Jump>{};
  final targets = <Instruction, Set<FunctionTarget>>{};
  final callableSources = <Instruction, Set<FunctionTarget>>{};
  final pendingExecution = <Instruction, Set<FunctionTarget>>{};
  final calls = <Instruction, Set<_Activation>>{};
  final allocationCalls = <Instruction, DirectCall>{};
  final callSites = <_CallSite>{};
  final readers = <_Activation>{};
  final unknownCalls = <Instruction>{};
  final externalCalls = <Instruction>{};
  final exits = <Instruction, ({bool normal, bool exceptional})>{};
  final operationEffects = <Instruction, Set<Effect>>{};
  final externalEffects = <Instruction, Set<Effect>>{};
  final effects = <Effect>{};
  final boundMethods = <FlowObject, Set<FunctionTarget>>{};
  final instantiations = <FlowObject, List<ValueType>>{};
  final environment = <TypeParameterType, ValueType>{};
  Map<TypeParameterType, ValueType> get executionEnvironment {
    final function = body;
    if (function is! IrFunction || function.typeBindings.isEmpty) {
      return environment;
    }
    return {
      ...environment,
      for (final binding in function.typeBindings)
        binding.parameter: switch (binding.value is Constant
            ? binding.value
            : values[binding.value]?.constant) {
          TypeConstant(:final representedType) => representedType,
          _ => binding.parameter,
        },
    };
  }

  FlowState? input;
  final normalParameterRanges = <int, FlowIntegerRange>{};
  _StateSummary? normalSummary;
  _StateSummary? exceptionalSummary;
  Object? firstExceptionSite;
  Map<Object, _StateSummary>? exceptionSources;
  FlowState? get normal => normalSummary?.exit;
  FlowState? get exceptional => exceptionalSummary?.exit;
  FlowValue returned = const FlowValue.bottom();
  FlowValue exception = const FlowValue.bottom();
  FlowValue stackTrace = const FlowValue.bottom();
  bool hasSemanticFailure = false;
  bool _hasEnvironment = false;
  bool repeated = false;
  bool recursive = false;

  bool mergeValue(
    Value value,
    FlowValue incoming, {
    bool widen = false,
    FlowIntegerRange? bound,
  }) {
    final previous = values[value] ?? const FlowValue.bottom();
    var joined = previous.join(incoming, widen: widen || recursive);
    if (bound != null) joined = joined.restrictIntegers(bound);
    if (joined == previous) return false;
    values[value] = joined;
    return true;
  }

  bool mergeEnvironment(Map<TypeParameterType, ValueType> incoming) {
    final complete = _completeEnvironment(body.target, incoming);
    if (!_hasEnvironment) {
      environment.addAll(complete);
      _hasEnvironment = true;
      return complete.isNotEmpty;
    }
    var changed = false;
    for (final entry in complete.entries) {
      final previous = environment[entry.key];
      final joined = previous == entry.value ? entry.value : entry.key;
      if (joined != previous) {
        environment[entry.key] = joined;
        changed = true;
      }
    }
    return changed;
  }
}

Map<TypeParameterType, ValueType> _completeEnvironment(
  FunctionTarget target,
  Map<TypeParameterType, ValueType> incoming,
) => {
  for (FunctionTarget? scope = target; scope != null; scope = scope.enclosing)
    for (final parameter in [
      ...scope.typeParameters,
      ...?scope.owner?.typeParameters,
    ])
      parameter: parameter,
  ...incoming,
};

const FlowResult _unreachable = FlowResult(
  value: FlowValue.bottom(),
  normal: null,
  exceptional: null,
);
final _null = FlowValue.constant(const Constant.nullValue());
final _typeError = FlowValue.unknown(ValueType.typeError);

// Missing entries denote an unrestricted value on the incoming path.
bool _joinRanges<K>(
  Map<K, FlowIntegerRange> known,
  Map<K, FlowIntegerRange> incoming, {
  bool widen = false,
}) {
  var changed = false;
  for (final key in known.keys.toList()) {
    final range = incoming[key];
    if (range == null) {
      known.remove(key);
      changed = true;
    } else {
      final joined = known[key]!.join(range, widen: widen);
      changed |= joined != known[key];
      known[key] = joined;
    }
  }
  return changed;
}

FlowStorageAccess _emptyStorageAccess() => (
  fields: <InstanceField>{},
  globals: <GlobalVariable>{},
  data: <NativeData>{},
  modules: <ModuleObject>{},
  context: false,
  cells: false,
  memory: false,
  writes: false,
  exposed: false,
  rawWrites: false,
);

// A static bound is not an object's runtime class. Only concrete constants,
// exact allocation types, and closed scalar representations establish metadata.
ValueType? _callableRuntimeType(FlowObject object, FlowState state) =>
    switch (state.callableRuntimeTypeOf(object)?.constant) {
      TypeConstant(:final representedType) => representedType,
      _ => null,
    };

FlowValue _runtimeTypeValue(FlowValue input, FlowState state) {
  FlowValue known(ValueType type) {
    final actual = type.reify();
    return actual.freeTypeParameters.isEmpty
        ? FlowValue.constant(TypeConstant(actual))
        : FlowValue.unknown(TypeMetadata.type);
  }

  FlowValue scalar(ValueType type) =>
      type == ValueType.integer ||
          type == ValueType.floating ||
          type == ValueType.boolean ||
          type == ValueType.nullType
      ? known(type)
      : FlowValue.unknown(TypeMetadata.type);

  return FlowValue.joined([
    for (final constant in input.constants) known(constant.runtimeValueType),
    for (final object in input.objects)
      object.callableStorage != null
          ? state.callableRuntimeTypeOf(object) ?? FlowValue.unknown(TypeMetadata.type)
          : object.type is ClassType || object.type is FunctionType
          ? known(object.type)
          : FlowValue.unknown(TypeMetadata.type),
    for (final address in input.addresses) scalar(address.type),
    for (final bound in input.unknownTypes) scalar(bound),
  ]);
}

Object? _typeKey(Iterable<ValueType> types) =>
    types.fold<Object?>(null, (key, type) => (key, type));

bool _sameValues(List<FlowValue> a, List<FlowValue> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

Set<Jump> _backEdges(Block entry) {
  final visited = <Block>{}, active = <Block>{};
  final result = <Jump>{};
  void visit(Block block) {
    if (!visited.add(block)) return;
    active.add(block);
    for (final jump in block.successors) {
      if (active.contains(jump.target)) {
        result.add(jump);
      } else {
        visit(jump.target);
      }
    }
    active.remove(block);
  }

  visit(entry);
  return result;
}

Map<Value, FlowIntegerRange>? _integerRefinements(
  Value condition,
  bool outcome,
  FlowValue Function(Value) read,
) {
  final (Value, Value, bool)? relation = switch (condition) {
    IntBinary(operator: .lessThan, :final left, :final right) =>
      outcome ? (left, right, true) : (right, left, false),
    IntBinary(operator: .lessOrEqual, :final left, :final right) =>
      outcome ? (left, right, false) : (right, left, true),
    IntBinary(operator: .greaterThan, :final left, :final right) =>
      outcome ? (right, left, true) : (left, right, false),
    IntBinary(operator: .greaterOrEqual, :final left, :final right) =>
      outcome ? (right, left, false) : (left, right, true),
    _ => null,
  };
  if (relation != null) {
    final (leftValue, rightValue, strict) = relation;
    final left = read(leftValue).integers, right = read(rightValue).integers;
    if (left == null || right == null) return {};
    if (strict &&
        (right.upper == FlowIntegerRange.minimum ||
            left.lower == FlowIntegerRange.maximum)) {
      return null;
    }
    final a = left.intersect(
      FlowIntegerRange(
        FlowIntegerRange.minimum,
        right.upper - (strict ? 1 : 0),
      ),
    );
    final b = right.intersect(
      FlowIntegerRange(left.lower + (strict ? 1 : 0), FlowIntegerRange.maximum),
    );
    return a == null || b == null ? null : {leftValue: a, rightValue: b};
  }
  if (condition case Equals(:final left, :final right, :final negated)) {
    for (final (value, constant) in [(left, right), (right, left)]) {
      if (read(constant).constant case ScalarConstant(value: 0)
          when read(value).addresses.isNotEmpty &&
              read(value).types.every((type) => type == ValueType.integer)) {
        return {
          value: outcome != negated
              ? FlowIntegerRange(0, 0)
              : FlowIntegerRange(
                  FlowIntegerRange.minimum,
                  FlowIntegerRange.maximum,
                  excludesZero: true,
                ),
        };
      }
    }
    final a = read(left).integers, b = read(right).integers;
    if (a == null || b == null) return {};
    if (outcome != negated) {
      final common = a.intersect(b);
      return common == null ? null : {left: common, right: common};
    }
    final result = <Value, FlowIntegerRange>{};
    for (final (value, range, excluded) in [
      (left, a, b.constant),
      (right, b, a.constant),
    ]) {
      if (excluded == null || !range.contains(excluded)) continue;
      if (range.constant == excluded) return null;
      if (range.lower == excluded) {
        result[value] = FlowIntegerRange(excluded + 1, range.upper);
      } else if (range.upper == excluded) {
        result[value] = FlowIntegerRange(range.lower, excluded - 1);
      } else if (excluded == 0) {
        result[value] = FlowIntegerRange(
          range.lower,
          range.upper,
          strideBits: range.strideBits,
          residue: range.residue,
          excludesZero: true,
        );
      }
    }
    return result;
  }
  return {};
}

({FlowValue value, bool mayThrow})? _integerOperation(
  Instruction operation,
  List<FlowValue> inputs,
) {
  if (inputs.length != 2) return null;
  final left = inputs.first.integers, right = inputs.last.integers;
  if (left == null || right == null) return null;
  ({FlowValue value, bool mayThrow}) result(FlowIntegerRange range) =>
      (value: FlowValue.integerRange(range), mayThrow: false);
  ({FlowValue value, bool mayThrow}) boolean(bool? value) => (
    value: value == null
        ? FlowValue.unknown(.boolean)
        : FlowValue.constant(Constant.boolean(value)),
    mayThrow: false,
  );
  if (operation case Equals(:final negated)) {
    if (left.intersect(right) == null) return boolean(negated);
    if (_equivalent(inputs.first, inputs.last)) return boolean(!negated);
    return boolean(null);
  }
  if (operation is! IntBinary) return null;
  switch (operation.operator) {
    case .add:
      return result(left.add(right));
    case .subtract:
      return result(left.subtract(right));
    case .multiply:
      return result(left.multiply(right));
    case .lessThan:
      return boolean(
        left.upper < right.lower
            ? true
            : left.lower >= right.upper
            ? false
            : null,
      );
    case .lessOrEqual:
      return boolean(
        left.upper <= right.lower
            ? true
            : left.lower > right.upper
            ? false
            : null,
      );
    case .greaterThan:
      return boolean(
        left.lower > right.upper
            ? true
            : left.upper <= right.lower
            ? false
            : null,
      );
    case .greaterOrEqual:
      return boolean(
        left.lower >= right.upper
            ? true
            : left.upper < right.lower
            ? false
            : null,
      );
    case .bitAnd:
      final mask = left.constant ?? right.constant;
      if (mask == -1) return result(left.constant == -1 ? right : left);
      return result(
        FlowIntegerRange(
          mask != null && mask >= 0 ? 0 : FlowIntegerRange.minimum,
          mask != null && mask >= 0 ? mask : FlowIntegerRange.maximum,
          strideBits: left.zeroBits > right.zeroBits
              ? left.zeroBits
              : right.zeroBits,
        ),
      );
    case .bitOr || .bitXor:
      if (left.constant == 0) return result(right);
      if (right.constant == 0) return result(left);
      final positive = left.lower >= 0 && right.lower >= 0;
      final upper = left.upper > right.upper ? left.upper : right.upper;
      return result(
        FlowIntegerRange(
          positive ? 0 : FlowIntegerRange.minimum,
          positive ? -1 >>> (64 - upper.bitLength) : FlowIntegerRange.maximum,
          strideBits: left.zeroBits < right.zeroBits
              ? left.zeroBits
              : right.zeroBits,
        ),
      );
    case .shiftLeft || .shiftRight || .unsignedShiftRight:
      final mayThrow = operation.checked && right.lower < 0;
      if (right.upper < 0) {
        return (value: const FlowValue.bottom(), mayThrow: true);
      }
      FlowIntegerRange value = FlowIntegerRange.full;
      if (left.constant == 0 ||
          operation.operator != .shiftRight && right.lower >= 64) {
        value = FlowIntegerRange(0, 0);
      } else if (right.constant == 0) {
        value = left;
      } else if (operation.operator == .shiftLeft) {
        final count = right.lower < 0 ? 0 : right.lower;
        final bits = left.zeroBits + count;
        value = right.upper < 63
            ? left.multiply(
                FlowIntegerRange(
                  1 << count,
                  1 << right.upper,
                  strideBits: count,
                ),
              )
            : FlowIntegerRange(
                FlowIntegerRange.minimum,
                FlowIntegerRange.maximum,
                strideBits: bits > 64 ? 64 : bits,
              );
      } else {
        final positiveCounts = right.intersect(
          FlowIntegerRange(1, FlowIntegerRange.maximum),
        );
        final counts = [
          right.lower < 0 ? 0 : right.lower,
          right.upper,
          if (operation.operator == .unsignedShiftRight &&
              left.lower < 0 &&
              positiveCounts != null)
            positiveCounts.lower,
        ];
        final values = [
          for (final number in [left.lower, left.upper])
            for (final count in counts)
              operation.operator == .shiftRight
                  ? number >> count
                  : number >>> count,
          if (operation.operator == .unsignedShiftRight &&
              left.lower < 0 &&
              left.upper >= 0) ...[
            for (final count in counts) ...[0, -1 >>> count],
          ],
        ]..sort();
        value = FlowIntegerRange(
          values.first,
          values.last,
          strideBits: left.zeroBits > right.upper
              ? left.zeroBits - right.upper
              : 0,
        );
      }
      return (value: FlowValue.integerRange(value), mayThrow: mayThrow);
    case .truncateDivide || .modulo || .remainder:
      return (
        value: right.constant == 0
            ? const FlowValue.bottom()
            : left.constant == 0
            ? FlowValue.constant(const Constant.integer(0))
            : FlowValue.unknown(.integer),
        mayThrow: operation.checked && right.contains(0),
      );
    case .divide:
      break;
  }
  return null;
}

FlowValue _referenceAddress(FlowValue input) {
  final carrier = input.carrierReferences;
  var value = const FlowValue.bottom();
  for (final constant in carrier.constants) {
    value = value.join(
      constant.type == .nullType
          ? FlowValue.constant(const Constant.integer(0))
          : FlowValue.address(FlowAddress(constant, 0)),
    );
  }
  for (final object in carrier.objects) {
    value = value.join(FlowValue.address(FlowAddress(object, 0)));
  }
  if (carrier.unknownTypes.isNotEmpty || carrier.addresses.isNotEmpty) {
    value = value.join(FlowValue.unknown(.integer).withReferences([carrier]));
  }
  return value;
}

FlowValue _addressArithmetic(IntBinary operation, List<FlowValue> inputs) {
  final left = inputs[0], right = inputs[1];
  final subtract = operation.operator == .subtract;
  var result = const FlowValue.bottom();
  bool scalar(FlowValue value) =>
      value.unknownTypes.isNotEmpty ||
      value.constants.isNotEmpty ||
      value.objects.isNotEmpty;
  void shifted(FlowValue base, FlowValue offset, {required bool negative}) {
    for (final address in base.addresses) {
      result = result.join(
        FlowValue.address(
          FlowAddress.ranged(
            address.base,
            _shiftOffsets(address.offsets, offset.integers, subtract: negative),
            retainedBase: address.retainedBase,
          ),
        ),
      );
    }
  }

  if (scalar(right)) shifted(left, right, negative: subtract);
  if (!subtract && scalar(left)) shifted(right, left, negative: false);
  if (subtract && left.addresses.isNotEmpty && right.addresses.isNotEmpty) {
    for (final a in left.addresses) {
      for (final b in right.addresses) {
        result = result.join(
          a.identity == b.identity && a.offsets != null && b.offsets != null
              ? FlowValue.integerRange(
                  _shiftOffsets(a.offsets, b.offsets, subtract: true)!,
                )
              : FlowValue.unknown(.integer),
        );
      }
    }
  }
  if (result.isBottom ||
      scalar(left) && scalar(right) ||
      subtract && scalar(left) && right.addresses.isNotEmpty ||
      !subtract && left.addresses.isNotEmpty && right.addresses.isNotEmpty) {
    result = result.join(FlowValue.unknown(.integer));
  }
  return result.withReferences([left.references, right.references]);
}

FlowIntegerRange? _shiftOffsets(
  FlowIntegerRange? base,
  FlowIntegerRange? amount, {
  bool subtract = false,
  int bits = 64,
}) {
  if (base == null || amount == null) return null;
  if ((base.constant, amount.constant) case (final left?, final right?)) {
    final value = (subtract ? left - right : left + right).toSigned(bits);
    return FlowIntegerRange(value, value);
  }
  final result = subtract ? base.subtract(amount) : base.add(amount);
  if (bits < 64 &&
      (result.lower < -(1 << (bits - 1)) || result.upper >= 1 << (bits - 1))) {
    return FlowIntegerRange.full;
  }
  return result;
}

Constant? _fold(
  Instruction operation,
  List<FlowValue> inputs,
  IrProgram program, [
  FlowState? state,
]) {
  // Dart's null equality never dispatches a user operator. A non-null bound
  // therefore decides this branch even when the other identity is unknown.
  if (operation is Equals || operation is Identical) {
    for (final (nullValue, other) in [
      (inputs.first, inputs.last),
      (inputs.last, inputs.first),
    ]) {
      if (nullValue.constant == const Constant.nullValue() &&
          !other.isBottom &&
          other.types.every((type) => !type.mayBeNull)) {
        return Constant.boolean(operation is Equals && operation.negated);
      }
    }
  }
  if (operation is Identical) {
    if (_equivalent(inputs.first, inputs.last)) {
      return const Constant.boolean(true);
    }
    if (inputs.every(
          (value) =>
              value.objects.isNotEmpty &&
              value.constants.isEmpty &&
              value.unknownTypes.isEmpty &&
              value.addresses.isEmpty &&
              value.objects.every((object) => object.site is Construct),
        ) &&
        !inputs.first.objects.any(
          (left) => inputs.last.objects.any(
            (right) => _mayAliasAcrossSummaries(left, right),
          ),
        )) {
      return const Constant.boolean(false);
    }
    if (inputs.first.constant case final ObjectConstant left) {
      if (inputs.last.constant case final ObjectConstant right) {
        return Constant.boolean(left.structuralKey == right.structuralKey);
      }
    }
    for (final (constant, allocated) in [
      (inputs.first, inputs.last),
      (inputs.last, inputs.first),
    ]) {
      if (constant.constant is ObjectConstant &&
          allocated.objects.isNotEmpty &&
          allocated.constants.isEmpty &&
          allocated.unknownTypes.isEmpty &&
          allocated.addresses.isEmpty &&
          allocated.objects.every((object) => object.type is ClassType)) {
        return const Constant.boolean(false);
      }
    }
  }
  if (state != null && operation is Equals && !operation.mayCallUserCode) {
    for (final (value, other) in [
      (inputs.first, inputs.last),
      (inputs.last, inputs.first),
    ]) {
      if (other.constant case ScalarConstant(type: final type, value: 0)
          when type == ValueType.integer && state.isMappedAddress(value)) {
        return Constant.boolean(operation.negated);
      }
    }
  }
  if (operation case Equals(:final negated)) {
    if (inputs.every(
      (value) =>
          value.constants.isEmpty &&
          value.objects.isEmpty &&
          value.unknownTypes.isEmpty &&
          value.addresses.length == 1,
    )) {
      final left = inputs.first.addresses.single,
          right = inputs.last.addresses.single;
      if (left.identity == right.identity &&
          left.offset != null &&
          right.offset != null) {
        return Constant.boolean((left.offset == right.offset) != negated);
      }
    }
  }
  final constants = inputs.map((value) => value.constant).toList();
  if (constants.any((value) => value == null)) return null;
  final scalars = constants
      .map((value) => value is ScalarConstant ? value.value : null)
      .toList();
  Object? result;
  try {
    switch (operation) {
      case IntBinary(:final operator):
        final left = scalars[0] as int;
        final right = scalars[1] as int;
        result = switch (operator) {
          .add => left + right,
          .subtract => left - right,
          .multiply => left * right,
          .divide => left / right,
          .truncateDivide => left ~/ right,
          .modulo => left % right,
          .remainder => left.remainder(right),
          .bitAnd => left & right,
          .bitOr => left | right,
          .bitXor => left ^ right,
          .shiftLeft => left << right,
          .shiftRight => left >> right,
          .unsignedShiftRight => left >>> right,
          .lessThan => left < right,
          .lessOrEqual => left <= right,
          .greaterThan => left > right,
          .greaterOrEqual => left >= right,
        };
      case NumericBinary(:final operator):
        final left = scalars[0] as num;
        final right = scalars[1] as num;
        result = switch (operator) {
          .add => left + right,
          .subtract => left - right,
          .multiply => left * right,
          .divide => left / right,
          .truncateDivide => left ~/ right,
          .modulo => left % right,
          .remainder => left.remainder(right),
          .lessThan => (_numericOrder(left, right) ?? 1) < 0,
          .lessOrEqual => (_numericOrder(left, right) ?? 1) <= 0,
          .greaterThan => (_numericOrder(left, right) ?? -1) > 0,
          .greaterOrEqual => (_numericOrder(left, right) ?? -1) >= 0,
        };
      case NumericNegate():
        result = -(scalars.single as num);
      case NumericToDouble():
        result = (scalars.single as num).toDouble();
      case Equals(:final negated)
          when constants.every((value) => value is ScalarConstant):
        result =
            (scalars[0] is num && scalars[1] is num
                ? _numericOrder(scalars[0] as num, scalars[1] as num) == 0
                : scalars[0] == scalars[1]) !=
            negated;
      case Equals(:final negated)
          when constants.every((value) => value is TypeConstant):
        result =
            (constants[0]!.structuralKey == constants[1]!.structuralKey) !=
            negated;
      case Identical()
          when constants.every(
            (value) =>
                value is ScalarConstant ||
                value is FunctionConstant ||
                value is TypeConstant,
          ):
        result = constants[0]!.structuralKey == constants[1]!.structuralKey;
      case TypeTest(:final testedType, :final negated)
          when testedType.freeTypeParameters.isEmpty:
        final checked = FlowValue.constant(constants.single!)
            .check(testedType, runtimeTypes: true);
        result = (!checked.mayFail) != negated;
      case RecordGet(slot: final index) when constants.single is RecordConstant:
        return (constants.single as RecordConstant).fields[index];
      case CollectionLength()
          when constants.single is SequenceConstant &&
              (constants.single!.type as ClassType).declaration ==
                  CoreTypes.list:
        return Constant.integer(
          (constants.single as SequenceConstant).elements.length,
        );
      case CollectionGet()
          when constants.first is SequenceConstant &&
              scalars[1] is int &&
              (constants.first!.type as ClassType).declaration ==
                  CoreTypes.list:
        final index = scalars[1] as int;
        final values = (constants.first as SequenceConstant).elements;
        return index >= 0 && index < values.length ? values[index] : null;
      case StringLength() when scalars.single is String:
        return Constant.integer((scalars.single as String).length);
      case StringConcat():
        result = (scalars[0] as String) + (scalars[1] as String);
      case StringFromCharCode():
        result = String.fromCharCode(scalars.single as int);
      case StringCodeUnitAt():
        result = (scalars[0] as String).codeUnitAt(scalars[1] as int);
      case StringFromCharCodes():
        List<Constant>? codes;
        if (constants.first case SequenceConstant(:final elements)) {
          codes = elements;
        } else if (constants.first case ObjectConstant(
          :final type,
          :final fields,
        )) {
          final storage = program.classes
              .where(
                (declaration) =>
                    declaration.type == (type as ClassType).declaration,
              )
              .firstOrNull
              ?.listStorage;
          if (storage == null) return null;
          if ((fields[storage.length], fields[storage.data])
              case (
                ScalarConstant(value: final int length),
                ObjectConstant(:final payload),
              )
              when length == payload.length) {
            codes = payload;
          }
        }
        if (codes == null) return null;
        if (codes.any(
          (code) => code is! ScalarConstant || code.value is! int,
        )) {
          return null;
        }
        result = String.fromCharCodes(
          codes.map((code) => (code as ScalarConstant).value as int),
          scalars[1] as int,
          scalars[2] as int?,
        );
      default:
        return null;
    }
  } on Object {
    // Runtime failures stay in the target program with their original effects.
    return null;
  }
  return switch (result) {
    bool value => Constant.boolean(value),
    int value => Constant.integer(value),
    double value => Constant.floating(value),
    String value => Constant.string(value),
    _ => null,
  };
}

// Use exact compareTo ordering, with IEEE NaN and signed-zero rules.
int? _numericOrder(num left, num right) => left.isNaN || right.isNaN
    ? null
    : left == 0 && right == 0
    ? 0
    : left.compareTo(right);
