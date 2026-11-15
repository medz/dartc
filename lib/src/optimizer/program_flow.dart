import 'package:dartc/ir.dart';

import 'flow_state.dart';
import 'flow_value.dart';
import 'integer_range.dart';
import 'memory_layout.dart';

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
}) {
  final _nativeEntries = Map<NativeCallbackTarget, FunctionTarget>.unmodifiable(
    nativeEntries,
  );
  final _entries = <FlowEntry>[];
  final _openEntries = <FunctionTarget>{};
  final _escapingReturns = <FunctionTarget>{};
  final _escapedCalls = <Object, _Activation>{};
  final _roots = <FunctionTarget, _Activation>{};
  final _calls = <_ContextKey, _Activation>{};
  final _callSites = <(_Activation, Instruction, FunctionTarget), _CallSite>{};
  final _pending = <_Activation>{};
  final _owners = <Object, FunctionTarget>{};
  final _cyclic = <FunctionTarget, Set<Block>>{};
  final _definitions = <FunctionTarget>{};
  FlowState? _externalState;
  final _escapingActivations = <_Activation>{};
  final _nativeActivations = <_Activation>{};
  final _nativeLookups = <_Activation>{};
  final _constructedReturns = <_Activation, FlowValue>{};
  ProgramFlowFacts? _facts;

  this {
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
    while (_pending.isNotEmpty) {
      final activation = _pending.first;
      _pending.remove(activation);
      _evaluate(activation);
    }
    return true;
  }

  void _validateEntry(FlowEntry entry) {
    if (program.implementationOf(entry.target) == null ||
        entry.target.kind == .closure ||
        entry.arguments.length != entry.target.parameterTypes.length) {
      throw ArgumentError('Entry requires a supplied body and every argument.');
    }
    for (final (index, value) in entry.arguments.indexed) {
      if (value.objects.isNotEmpty ||
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
          case FunctionConstant(:final target):
            if (program.implementationOf(target.implementation) == null) {
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
      entry.arguments,
      open
          ? (_externalState ??= FlowState(program, memoryLayout: memoryLayout))
          : FlowState(program, memoryLayout: memoryLayout),
    );
  }

  void _supply(
    _Activation activation,
    List<FlowValue> arguments,
    FlowState input,
  ) {
    if (arguments.length != activation.body.target.parameterTypes.length) {
      throw StateError('Invocation lost semantic arguments.');
    }
    var changed = false;
    for (final (index, value) in arguments.indexed) {
      final joined = activation.arguments[index].join(
        value,
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
    if (changed) _pending.add(activation);
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
  }) {
    if (arguments.any((value) => value.isBottom)) return _unreachable;
    final target = source.implementation;
    if (operation case FunctionCall(target: final bound?)
        when bound != target) {
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
        final expected = target.signature.parameters[index].substitute(
          environment,
        );
        final checked = arguments[slot].check(expected);
        failedCheck |= checked.mayFail;
        arguments[slot] = checked.value;
      }
      if (arguments.any((value) => value.isBottom)) {
        caller.operationEffects[operation] = {
          ...?caller.operationEffects[operation],
          Effect.mayThrow,
        };
        return FlowResult(exceptional: input.copy());
      }
    }
    caller.targets.putIfAbsent(operation, () => {}).add(target);
    _definitions.add(target);
    final body = program.implementationOf(target);
    if (body is! IrFunction) {
      caller.externalCalls.add(operation);
      final effects = body is IrExternal ? body.effects : Effect.values.toSet();
      caller.externalEffects.putIfAbsent(operation, () => {}).addAll(effects);
      return _external(
        caller,
        block,
        operation,
        arguments,
        input,
        target.returnType.substitute(environment),
        effects: effects,
      );
    }
    final path = _recursivePath(caller, target, arguments);
    final site = _callSites.putIfAbsent((
      caller,
      operation,
      target,
    ), () => _CallSite(caller, operation, target));
    final repeated =
        path.isNotEmpty ||
        caller.repeated ||
        _loopBlocks(caller.body).contains(block);
    final projected = input.project(arguments);
    final aliases = <(int, int)>[
      for (var i = 0; i < arguments.length; i++)
        for (var j = 0; j < i; j++)
          if (_equivalent(arguments[i], arguments[j])) (i, j),
    ];
    final plain = [for (final value in arguments) value.withSources(const [])];
    late final _Activation callee;
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
        aliasKey,
      );
      var key = site.contexts[local];
      if (key != local) {
        final keyState = projected.copy()..retainSources((_) => false);
        final precise = _ContextKey(
          target,
          plain,
          environment,
          keyState.structuralKey,
          repeated,
          aliasKey,
        );
        if (key == null || key == precise) {
          key = precise;
        } else {
          final previous = _calls[key]!;
          // Only shared exact executions need a separate joining summary.
          if (previous.callSites.length == 1 &&
              previous.callSites.contains(site)) {
            _calls.remove(key);
            _calls[local] = previous;
          }
          key = local;
        }
        site.contexts[local] = key;
      }
      callee = _calls.putIfAbsent(key!, () => _Activation(body));
    }
    if (repeated && !callee.repeated) {
      callee.repeated = true;
      _pending.add(callee);
    }
    if (path.isNotEmpty) {
      site.recursive = true;
      for (final cycle in path) {
        cycle.recursive = true;
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
    if (callee.mergeEnvironment(environment)) _pending.add(callee);
    caller.calls.putIfAbsent(operation, () => {}).add(callee);
    callee.readers.add(caller);
    callee.callSites.add(site);
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
    _supply(callee, supplied, projected);

    FlowObject mapObject(FlowObject object) {
      if (site.recursive ||
          callee.input!.containsObject(object) ||
          arguments.any(
            (value) =>
                value.objects.contains(object) ||
                value.references.objects.contains(object),
          )) {
        return object;
      }
      return site.allocations.putIfAbsent(
        object,
        () => FlowObject(
          object.site,
          _AllocationContext(object, site),
          type: object.type,
          variant: object.variant,
        ),
      );
    }

    FlowValue mapValue(FlowValue value, {bool normal = false}) {
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
        final index = parameters.indexWhere(
          (parameter) => identical(parameter, source.value),
        );
        if (index >= 0) sources.addAll(arguments[index].sources);
      }
      return value.mapObjects(mapObject).withSources(sources);
    }

    FlowState? apply(FlowState? after, {bool normal = false}) => after == null
        ? null
        : input.applySummary(
            projected,
            after.project([...arguments, callee.returned, callee.exception]),
            mapObject: mapObject,
            mapValue: (value) => mapValue(value, normal: normal),
            preservesInputSources: callee.effects.every(
              (effect) => effect == .readsStorage || effect == .mayThrow,
            ),
          );
    final invoked = FlowResult(
      value: mapValue(callee.returned),
      normal: apply(callee.normal, normal: true),
      exceptional: apply(callee.exceptional),
      exception: mapValue(callee.exception),
      stackTrace: mapValue(callee.stackTrace),
    );
    return failedCheck
        ? _joinResult(invoked, FlowResult(exceptional: input.copy()))
        : invoked;
  }

  List<_Activation> _recursivePath(
    _Activation caller,
    FunctionTarget target,
    List<FlowValue> arguments,
  ) {
    bool matches(_Activation candidate) {
      if (candidate.body.target != target) return false;
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
        if (child.containsKey(parent)) continue;
        child[parent] = item;
        pending.add(parent);
      }
    }
    return const [];
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
      body.entry: activation.input!.copy()
        ..retainSources((source) => availableAt(source, body.entry)),
    };
    final incomingRanges = <Block, Map<Value, FlowIntegerRange>>{
      body.entry: {},
    };
    final pending = <Block>{body.entry};
    final readers = <Value, Set<Block>>{};
    late Block readingBlock;
    late Map<Value, FlowIntegerRange> ranges;
    bool mergeValue(Value value, FlowValue incoming, {bool widen = false}) {
      if (!activation.mergeValue(value, incoming, widen: widen)) return false;
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
      for (final source in value.sources) {
        if (!identical(source.activation, activation)) continue;
        if (ranges[source.value] case final range?) {
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
                test.testedType.substitute(activation.environment),
                negated: outcome == test.negated,
              )
              .value;
        case UnwindValue():
          return FlowValue.unknown(value.type);
        default:
          (readers[value] ??= {}).add(readingBlock);
          final known = constrained(
            activation.values[value] ?? const FlowValue.bottom(),
          );
          return switch (ranges[value]) {
            final range? => known.restrictIntegers(range),
            null => known,
          };
      }
    }

    void edge(
      Jump jump,
      FlowState state, {
      FlowValue? exception,
      FlowValue? stackTrace,
      Map<Value, FlowIntegerRange>? refinements,
    }) {
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
      activation.mergePoint(activation.edgeStates, jump, state);
      // Stored aliases refer to the previous binding when a loop re-enters.
      final nextState = state.copy()
        ..retainSources((source) => availableAt(source, jump.target));
      var changed = false;
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
      if (incomingRanges[jump.target] case final previous?) {
        for (final value in previous.keys.toList()) {
          final next = nextRanges[value];
          if (next == null) {
            previous.remove(value);
            changed = true;
          } else {
            final joined = previous[value]!.join(next, widen: widen);
            changed |= joined != previous[value];
            previous[value] = joined;
          }
        }
      } else {
        incomingRanges[jump.target] = nextRanges;
        changed = true;
      }
      if (incoming[jump.target] case final previous?) {
        changed = previous.join(nextState, widen: widen) || changed;
      } else {
        incoming[jump.target] = nextState;
        changed = true;
      }
      if (changed) pending.add(jump.target);
    }

    void exceptional(
      FlowState state,
      FlowValue exception,
      FlowValue stackTrace,
    ) {
      if (escapes && !_nativeActivations.contains(activation)) {
        state.escape([exception, stackTrace]);
        _admitEscaped(state);
      }
      final joinedException = activation.exception.join(exception);
      final joinedTrace = activation.stackTrace.join(stackTrace);
      summaryChanged |=
          joinedException != activation.exception ||
          joinedTrace != activation.stackTrace;
      activation.exception = joinedException;
      activation.stackTrace = joinedTrace;
      if (activation.exceptional == null) {
        activation.exceptional = state.copy();
        summaryChanged = true;
      } else {
        summaryChanged =
            activation.exceptional!.join(state, widen: activation.recursive) ||
            summaryChanged;
      }
    }

    while (pending.isNotEmpty) {
      final block = pending.first;
      pending.remove(block);
      readingBlock = block;
      ranges = {...incomingRanges[block]!};
      activation.blocks.add(block);
      FlowState? state = incoming[block]!.copy();
      FlowResult evaluate(Instruction operation) {
        activation.mergePoint(activation.before, operation, state!);
        var result = _operation(
          activation,
          block,
          operation,
          operation.inputs.map(read).toList(),
          state,
          read,
        );
        final type = operation.type.substitute(activation.environment);
        var bounded = result.value;
        if (bounded.types.any((actual) => !type.accepts(actual))) {
          // Caller bounds also constrain unresolved receiver type arguments.
          bounded = bounded.check(type).value;
        }
        bounded = constrained(bounded);
        if (bounded != result.value) {
          result = FlowResult(
            value: bounded,
            normal: bounded.isBottom ? null : result.normal,
            exceptional: result.exceptional,
            exception: result.exception,
            stackTrace: result.stackTrace,
            effects: result.effects,
          );
        }
        mergeValue(operation, result.value.withSource(operation, activation));
        ranges.remove(operation);
        if (result.value.integers case final range?
            when range != FlowIntegerRange.full) {
          ranges[operation] = range;
        }
        if (result.normal != null) {
          activation.mergePoint(activation.after, operation, result.normal!);
        }
        if (result.exceptional != null) {
          activation.exceptions[operation] =
              (activation.exceptions[operation] ?? const FlowValue.bottom())
                  .join(result.exception);
          activation.traces[operation] =
              (activation.traces[operation] ?? const FlowValue.bottom()).join(
                result.stackTrace,
              );
          activation.mergePoint(
            activation.thrown,
            operation,
            result.exceptional!,
          );
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
          exceptional(thrown, result.exception, result.stackTrace);
        }
        state = result.normal;
        if (state == null) break;
      }
      if (state == null) continue;
      switch (block.end) {
        case Return(:final value):
          final returned = value == null ? _null : read(value);
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
          if (activation.normal == null) {
            activation.normal = state.copy();
            summaryChanged = true;
          } else {
            summaryChanged =
                activation.normal!.join(state, widen: activation.recursive) ||
                summaryChanged;
          }
        case final Jump jump:
          edge(jump, state);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final value = read(condition);
          if (value.isBottom) break;
          if (value.constant case ScalarConstant(value: final bool known)) {
            edge(known ? ifTrue : ifFalse, state);
          } else {
            final yes = _integerRefinements(condition, true, read);
            final no = _integerRefinements(condition, false, read);
            if (yes != null) edge(ifTrue, state, refinements: yes);
            if (no != null) edge(ifFalse, state, refinements: no);
          }
        case Invoke(:final operation, :final onReturn, :final onThrow):
          final result = evaluate(operation);
          if (onReturn != null && result.normal != null) {
            edge(onReturn, result.normal!);
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
            exceptional(state, value, trace);
          } else {
            edge(onThrow, state, exception: value, stackTrace: trace);
          }
        case ExhaustivenessFailure(:final onThrow):
          if (onThrow == null) {
            exceptional(
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
    if (activation.exceptional != null) activation.effects.add(Effect.mayThrow);
    summaryChanged |= beforeEffects != activation.effects.length;
    if (escapes) {
      for (final state in [activation.normal, activation.exceptional]) {
        if (state != null) _publishExternal(state);
      }
    }
    if (summaryChanged) _pending.addAll(activation.readers);
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
    final resultType = operation.type.substitute(activation.environment);
    final repeated =
        activation.repeated || _loopBlocks(activation.body).contains(block);
    FlowObject allocate(Instruction site) => FlowObject(
      site,
      activation,
      type: site.type.substitute(activation.environment),
    );
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
      repeated: repeated,
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
        if (stored.exceptional != null) Effect.mayThrow,
      };
      return stored;
    }
    switch (operation) {
      case MakeInvocation():
        throw StateError('Normalize Invocation before program flow.');
      case DirectCall(:final target, :final ownerType, :final typeArguments):
        final environment = _environment(
          target,
          ownerType,
          typeArguments,
          activation,
        );
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
      case InstantiateFunction(:final function, :final typeArguments):
        return _instantiate(
          activation,
          operation,
          read(function),
          [
            for (final type in typeArguments)
              type.substitute(activation.environment),
          ],
          state,
          repeated: repeated,
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
              repeated: repeated,
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
      case ReferenceAddress():
        var value = const FlowValue.bottom();
        final input = inputs.single;
        for (final constant in input.constants) {
          value = value.join(
            constant.type == .nullType
                ? FlowValue.constant(const Constant.integer(0))
                : FlowValue.address(FlowAddress(constant, 0)),
          );
        }
        for (final object in input.objects) {
          value = value.join(FlowValue.address(FlowAddress(object, 0)));
        }
        if (input.unknownTypes.isNotEmpty || input.addresses.isNotEmpty) {
          value = value.join(
            FlowValue.unknown(.integer).withReferences([input]),
          );
        }
        activation.operationEffects[operation] = const {Effect.readsStorage};
        return FlowResult(value: value, normal: state.copy());
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
        var value = const FlowValue.bottom();
        for (final address in input.addresses) {
          value = value.join(
            address.offset == 0
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
      case ReifyType(:final template):
        final type = template.substitute(activation.environment);
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
          exceptional: state.copy(),
        );
      case TypeTest(:final testedType, :final negated):
        final expected = testedType.substitute(activation.environment);
        final value = inputs.single;
        bool? matches;
        if (expected.freeTypeParameters.isEmpty &&
            value.types.every((type) => type.freeTypeParameters.isEmpty)) {
          if (value.types.every(expected.accepts)) {
            matches = true;
          } else if (value.unknownTypes.isEmpty &&
              value.types.every((type) => !expected.accepts(type))) {
            matches = false;
          }
        }
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
          exceptional: operation.mayThrow ? state.copy() : null,
        );
      case TypeCast() || NullCheck():
        final checked = inputs.single.check(
          operation is NullCheck ? ValueType.object : resultType,
        );
        activation.operationEffects[operation] = {
          if (checked.mayFail) Effect.mayThrow,
        };
        return FlowResult(
          value: checked.value,
          normal: checked.value.isBottom ? null : state.copy(),
          exceptional: checked.mayFail ? state.copy() : null,
        );
      case TypeView() || UncheckedCast():
        final value = inputs.single.check(resultType).value;
        activation.operationEffects[operation] = const {};
        return FlowResult(
          value: value,
          normal: value.isBottom ? null : state.copy(),
        );
      default:
        final folded = _fold(operation, inputs, program);
        if (folded != null) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: FlowValue.constant(folded),
            normal: state.copy(),
            exceptional: null,
          );
        }
        if (operation is Equals &&
            inputs.first.types.every(ValueType.typeType.accepts)) {
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
            value: result.value.withReferences(
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
                    .withReferences(inputs.map((value) => value.references)),
          normal: resultType == .never ? null : next,
          exceptional: operation.mayThrow ? next.copy() : null,
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
        (object) => object.type is FunctionType,
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
          argument.substitute(activation.environment),
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
          operation.type.substitute(activation.environment),
        );
        result = _joinResult(
          result,
          FlowResult(
            value: checked.value,
            normal: checked.value.isBottom ? null : invoked.normal,
            exceptional: checked.mayFail
                ? _joinState(invoked.exceptional, invoked.normal)
                : invoked.exceptional,
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
          operation.type.substitute(activation.environment),
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
    FlowState state,
  ) {
    final actual = target.reifiedSignature.substitute(
      target.environmentFor(receiverType),
    );
    final expected = site.type.substitute(activation.environment);
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
      ..retain(
        object,
        [_receiverValue(receiver, receiverType)],
        repeated:
            activation.repeated || _loopBlocks(activation.body).contains(block),
      );
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
        FlowValue.unknown(site.type.substitute(activation.environment)),
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
        owner.substitute(caller.environment) as ClassType,
      ),
    for (final (index, type) in arguments.indexed)
      target.typeParameters[index]: type.substitute(caller.environment),
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
  }) {
    FlowResult result = _unreachable;
    final appliedArguments = [
      for (final type
          in typeArguments ??
              (site is FunctionCall ? site.typeArguments : const <ValueType>[]))
        type.substitute(activation.environment),
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

    for (final constant in function.constants.whereType<FunctionConstant>()) {
      final signature = constant.type as FunctionType;
      if (!accepts(FlowValue.constant(constant), signature)) continue;
      final effective = appliedArguments.isEmpty && checkAllArguments
          ? [
              for (final parameter in signature.typeParameters)
                parameter.defaultType ?? parameter.bound,
            ]
          : appliedArguments;
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
            type: owner!.substitute(activation.environment),
          ),
          target,
          arguments,
          repeated:
              activation.repeated ||
              _loopBlocks(activation.body).contains(block),
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
      final signature = object.type as FunctionType;
      if (!accepts(FlowValue.object(object), signature)) continue;
      final effective = appliedArguments.isEmpty && checkAllArguments
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
        case InstantiateFunction() || InstantiateFunctionFrom():
          final creator = _creator(object);
          result = _joinResult(
            result,
            _call(
              activation,
              block,
              site,
              captures.single,
              positional,
              named,
              state,
              typeArguments: creator.instantiations[_original(object)]!,
              checkAllArguments: checkAllArguments,
              resultSource: resultSource,
            ),
          );
        case MakeClosure(:final target):
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
                ..._creator(object).environment,
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
          site.type.substitute(activation.environment),
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
  }) {
    effects ??= operation.effects;
    activation.externalEffects.putIfAbsent(operation, () => {}).addAll(effects);
    final next = state.copy();
    next.escape(inputs);
    if (effects.contains(Effect.writesStorage)) {
      next.invalidate([next.exposedValues]);
    }
    if (effects.contains(Effect.callsUserCode)) {
      // Re-entry follows values that crossed this boundary or declared exports.
      _admitEscaped(next);
      for (final callback in {
        ..._escapingActivations,
        for (final target in _openEntries) _roots[target]!,
      }) {
        callback.readers.add(activation);
        _supply(callback, callback.arguments, next.project(callback.arguments));
        if (callback.normal != null) {
          next.join(callback.normal!.project(const []));
        }
        if (callback.exceptional != null) {
          next.join(callback.exceptional!.project(const []));
        }
      }
    }
    return FlowResult(
      value: resultType == .never
          ? const FlowValue.bottom()
          : FlowValue.unknown(resultType)
                .join(next.exposedValues.check(resultType).value)
                .withSources(const [])
                .withReferences(inputs.map((value) => value.references)),
      normal: resultType == .never ? null : next,
      exceptional: effects.contains(Effect.mayThrow) ? next.copy() : null,
    );
  }

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

  void _admitEscaped(FlowState state) {
    final reachable = state.exposedValues;
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
                FlowValue.unknown(type.substitute(environment)),
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
            ...creator.environment,
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
    if (type != ValueType.nullClass) return value.check(type).value;
    return FlowValue.constant(const Constant.nullValue())
        .withSources(value.sources);
  }

  Iterable<ClassType> _receiverTypes(FlowValue value) sync* {
    final seen = <ClassType>{};
    for (final type in [
      ...value.constants.map((constant) => constant.type),
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
      if (bound.mayBeNull && seen.add(ValueType.nullClass)) {
        yield ValueType.nullClass;
      }
      if (bound.nonNullable is FunctionType ||
          bound.nonNullable == ValueType.function) {
        if (seen.add(ValueType.function)) yield ValueType.function;
        continue;
      }
      const primitiveTypes = <ClassType>[
        ValueType.integer,
        ValueType.floating,
        ValueType.boolean,
        ValueType.string,
      ];
      for (final type in primitiveTypes) {
        if (value.mayHaveInstance(type) && seen.add(type)) yield type;
      }
      if (primitiveTypes.contains(bound.nonNullable)) continue;
      for (final declaration in program.classes) {
        final type = declaration.type;
        if (!type.isAbstract && value.mayHaveInstance(type) && seen.add(type)) {
          yield type;
        }
      }
    }
  }

  Set<Block> _loopBlocks(IrCallable body) => body is! IrFunction
      ? const {}
      : _cyclic.putIfAbsent(body.target, () => _cyclicBlocks(body.blocks));
}

/// Immutable queries over the converged activations of one graph.
final class ProgramFlowFacts._(final ProgramFlow _flow) {
  /// The exact verified graph used to establish these facts.
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

  /// Entries whose callers admit the full declared argument bounds.
  Set<FunctionTarget> get openEntries {
    _check();
    return Set.unmodifiable(_flow._openEntries);
  }

  /// Entry returns visible to an unknown outside consumer.
  Set<FunctionTarget> get escapingReturns {
    _check();
    return Set.unmodifiable(_flow._escapingReturns);
  }

  /// Bodies and imports reached by executable calls.
  Set<FunctionTarget> get definitions {
    _check();
    return Set.unmodifiable(_flow._definitions);
  }

  /// Verifies graph identity and rejects facts invalidated by new inputs.
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

  Iterable<_Activation> get _activations sync* {
    yield* _flow._roots.values;
    yield* _flow._calls.values;
    yield* _flow._escapedCalls.values;
  }

  /// Opaque activation identities for context-specific queries.
  Iterable<Object> activationsOf(FunctionTarget target) {
    _check();
    return List.unmodifiable(
      _activations.where((a) => a.body.target == target.implementation),
    );
  }

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
    bool descendsFrom(FlowObject value, FlowObject ancestor) {
      while (value != ancestor) {
        if (value.activation case _AllocationContext(:final original)) {
          value = original;
        } else {
          return false;
        }
      }
      return true;
    }

    return descendsFrom(left, right) || descendsFrom(right, left);
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
                value.test.testedType.substitute(item.environment),
                negated: value.outcome == value.test.negated,
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

  /// Resolved source targets; unknown alternatives are reported separately.
  Set<FunctionTarget> targetsOf(Instruction operation, {Object? activation}) =>
      Set.unmodifiable(
        _at(
          operation,
          activation,
        ).expand((item) => item.targets[operation] ?? const <FunctionTarget>{}),
      );

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
          for (final callee in item.calls[operation] ?? <_Activation>{})
            ...callee.effects,
        ],
      });

  /// Whether discarding an unused operation preserves effects and termination.
  bool canDiscard(Instruction operation, {Object? activation}) {
    final exits = exitsOf(operation, activation: activation);
    if (!exits.normal || exits.exceptional) return false;
    for (final item in _at(operation, activation)) {
      if (!_discardableOperation(item, operation, {})) return false;
    }
    return true;
  }

  bool _discardableOperation(
    _Activation activation,
    Instruction operation,
    Set<_Activation> visiting,
  ) {
    if (activation.unknownCalls.contains(operation) ||
        activation.externalCalls.contains(operation)) {
      return false;
    }
    final callees = activation.calls[operation] ?? const <_Activation>{};
    // Pure initialization may wait until a later read, even for writable storage.
    final binding =
        operation is LoadGlobal &&
        operation.global.initializer != null &&
        callees.isNotEmpty &&
        callees.every(
          (callee) =>
              callee.body.target ==
                  operation.global.initializer!.implementation &&
              callee.effects.every((effect) => effect == .allocates),
        );
    for (final effect in {
      ...?activation.operationEffects[operation],
      ...?activation.externalEffects[operation],
    }) {
      if (effect != .readsStorage &&
          effect != .allocates &&
          effect != .mayThrow &&
          !(effect == .writesStorage && binding)) {
        return false;
      }
    }
    for (final callee in callees) {
      if (!_discardableBody(callee, visiting)) return false;
    }
    return true;
  }

  bool _discardableBody(_Activation activation, Set<_Activation> visiting) {
    if (!visiting.add(activation) ||
        activation.recursive ||
        activation.body is! IrFunction ||
        activation.normal == null ||
        activation.exceptional != null) {
      return false;
    }
    final body = activation.body as IrFunction;
    if (body.bodyKind != .synchronous ||
        _cyclicBlocks(body.blocks, edges: activation.edges).isNotEmpty ||
        activation.unknownCalls.isNotEmpty ||
        activation.externalCalls.isNotEmpty) {
      return false;
    }
    for (final operation in {
      ...activation.operationEffects.keys,
      ...activation.externalEffects.keys,
      ...activation.calls.keys,
    }) {
      if (!_discardableOperation(activation, operation, visiting)) return false;
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
  final List<FlowValue> arguments,
  Map<TypeParameterType, ValueType> environment,
  final Object state,
  final bool repeated,
  final Object? aliases,
) {
  final Map<TypeParameterType, ValueType> environment = Map.unmodifiable(
    environment,
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

final class _CallSite(
  final _Activation caller,
  final Instruction operation,
  final FunctionTarget target,
) {
  final contexts = <_ContextKey, _ContextKey>{};
  final allocations = <FlowObject, FlowObject>{};
  bool recursive = false;
}

final class _AllocationContext(final FlowObject original, final _CallSite site);

FlowObject _original(FlowObject object) {
  while (object.activation is _AllocationContext) {
    object = (object.activation as _AllocationContext).original;
  }
  return object;
}

_Activation _creator(FlowObject object) =>
    _original(object).activation as _Activation;

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
    origins.add(constant.target.implementation);
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

final class _Activation(final IrCallable body) {
  late final dominance = ValueDominance(body as IrFunction);
  late final Set<Jump> backEdges = switch (body) {
    IrFunction(:final entry) => _backEdges(entry),
    _ => {},
  };
  final List<FlowValue> arguments = [
    for (final _ in body.target.parameterTypes) const FlowValue.bottom(),
  ];
  final values = <Value, FlowValue>{};
  final edgeStates = <Jump, FlowState>{};
  final before = <Instruction, FlowState>{};
  final after = <Instruction, FlowState>{};
  final thrown = <Instruction, FlowState>{};
  final exceptions = <Instruction, FlowValue>{};
  final traces = <Instruction, FlowValue>{};
  final blocks = <Block>{};
  final edges = <Jump>{};
  final targets = <Instruction, Set<FunctionTarget>>{};
  final calls = <Instruction, Set<_Activation>>{};
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
  FlowState? input;
  FlowState? normal;
  FlowState? exceptional;
  FlowValue returned = const FlowValue.bottom();
  FlowValue exception = const FlowValue.bottom();
  FlowValue stackTrace = const FlowValue.bottom();
  bool _hasEnvironment = false;
  bool repeated = false;
  bool recursive = false;

  void mergePoint<T extends Object>(
    Map<T, FlowState> points,
    T operation,
    FlowState state,
  ) {
    if (points[operation] case final known?) {
      known.join(state);
    } else {
      points[operation] = state.copy();
    }
  }

  bool mergeValue(Value value, FlowValue incoming, {bool widen = false}) {
    final previous = values[value] ?? const FlowValue.bottom();
    final joined = previous.join(incoming, widen: widen || recursive);
    if (joined == previous) return false;
    values[value] = joined;
    return true;
  }

  bool mergeEnvironment(Map<TypeParameterType, ValueType> incoming) {
    final complete = <TypeParameterType, ValueType>{
      for (
        FunctionTarget? scope = body.target;
        scope != null;
        scope = scope.enclosing
      )
        for (final parameter in [
          ...scope.typeParameters,
          ...?scope.owner?.typeParameters,
        ])
          parameter: parameter,
      ...incoming,
    };
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

const FlowResult _unreachable = FlowResult(
  value: FlowValue.bottom(),
  normal: null,
  exceptional: null,
);
final _null = FlowValue.constant(const Constant.nullValue());

FlowState? _joinState(FlowState? a, FlowState? b) =>
    a == null ? b?.copy() : (a.copy()..join(b ?? a));

FlowResult _joinResult(FlowResult left, FlowResult right) {
  return FlowResult(
    value: left.value.join(right.value),
    normal: _joinState(left.normal, right.normal),
    exceptional: _joinState(left.exceptional, right.exceptional),
    exception: left.exception.join(right.exception),
    stackTrace: left.stackTrace.join(right.stackTrace),
    effects: {...left.effects, ...right.effects},
  );
}

Object? _typeKey(Iterable<ValueType> types) =>
    types.fold<Object?>(null, (key, type) => (key, type));

bool _sameValues(List<FlowValue> a, List<FlowValue> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

Set<Block> _cyclicBlocks(Iterable<Block> blocks, {Set<Jump>? edges}) {
  final indices = <Block, int>{};
  final low = <Block, int>{};
  final active = <Block>{};
  final stack = <Block>[];
  final cyclic = <Block>{};
  var index = 0;
  void visit(Block block) {
    indices[block] = low[block] = index++;
    stack.add(block);
    active.add(block);
    for (final edge in block.successors) {
      if (edges != null && !edges.contains(edge)) continue;
      final next = edge.target;
      if (!indices.containsKey(next)) {
        visit(next);
        if (low[next]! < low[block]!) low[block] = low[next]!;
      } else if (active.contains(next) && indices[next]! < low[block]!) {
        low[block] = indices[next]!;
      }
    }
    if (indices[block] != low[block]) return;
    final component = <Block>[];
    Block item;
    do {
      item = stack.removeLast();
      active.remove(item);
      component.add(item);
    } while (!identical(item, block));
    if (component.length > 1 ||
        block.successors.any(
          (edge) =>
              identical(edge.target, block) &&
              (edges == null || edges.contains(edge)),
        )) {
      cyclic.addAll(component);
    }
  }

  for (final block in blocks) {
    if (!indices.containsKey(block)) visit(block);
  }
  return cyclic;
}

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
      if (mask != null && mask >= 0) return result(FlowIntegerRange(0, mask));
      if (mask == -1) return result(left.constant == -1 ? right : left);
    case .bitOr || .bitXor:
      if (left.constant == 0) return result(right);
      if (right.constant == 0) return result(left);
    case .shiftLeft || .shiftRight || .unsignedShiftRight:
      final mayThrow = operation.checked && right.lower < 0;
      if (right.upper < 0) {
        return (value: const FlowValue.bottom(), mayThrow: true);
      }
      FlowIntegerRange value = FlowIntegerRange.full;
      if (left.constant == 0 ||
          operation.operator == .unsignedShiftRight && right.lower >= 64) {
        value = FlowIntegerRange(0, 0);
      } else if (right.constant == 0) {
        value = left;
      } else if (operation.operator != .shiftLeft) {
        final counts = [
          right.lower < 0 ? 0 : right.lower,
          right.upper,
          if (operation.operator == .unsignedShiftRight &&
              left.lower < 0 &&
              right.contains(1))
            1,
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
        value = FlowIntegerRange(values.first, values.last);
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
  IrProgram program,
) {
  if (operation is Identical) {
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
        result = testedType.accepts(constants.single!.type) != negated;
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
