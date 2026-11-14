import 'package:dartc/ir.dart';

import 'flow_state.dart';
import 'flow_value.dart';

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
}) {
  final _entries = <FlowEntry>[];
  final _openEntries = <FunctionTarget>{};
  final _escapingReturns = <FunctionTarget>{};
  final _escapedCalls = <Object, _Activation>{};
  final _roots = <FunctionTarget, _Activation>{};
  final _calls = <(_Activation, Instruction, FunctionTarget), _Activation>{};
  final _pending = <_Activation>{};
  final _owners = <Object, FunctionTarget>{};
  final _cyclic = <FunctionTarget, Set<Block>>{};
  final _definitions = <FunctionTarget>{};
  FlowState? _externalState;
  final _escapingActivations = <_Activation>{};
  ProgramFlowFacts? _facts;

  this {
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
      if (value.objects.isNotEmpty) {
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
      for (final constant in value.constants.whereType<FunctionConstant>()) {
        if (program.implementationOf(constant.target) == null) {
          throw ArgumentError(
            'Entry function value belongs to another program.',
          );
        }
      }
    }
  }

  void _enterRoot(FlowEntry entry, {required bool open}) {
    if (entry.arguments.any((value) => value.isBottom)) return;
    final activation = _roots.putIfAbsent(
      entry.target,
      () => _Activation(program.implementationOf(entry.target)!, null),
    );
    activation.repeated |= open;
    activation.mergeEnvironment(const {});
    _supply(
      activation,
      entry.arguments,
      open ? (_externalState ??= FlowState(program)) : FlowState(program),
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
      final joined = activation.arguments[index].join(value);
      changed |= joined != activation.arguments[index];
      activation.arguments[index] = joined;
    }
    if (activation.input == null) {
      activation.input = input.copy();
      changed = true;
    } else {
      changed = activation.input!.join(input) || changed;
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
  }) {
    if (arguments.any((value) => value.isBottom)) return _unreachable;
    final target = source.implementation;
    environment = {...environment};
    if (target.kind.hasReceiver && arguments.isNotEmpty) {
      final types = arguments.first.types.toSet();
      if (types.length == 1 && types.single is ClassType) {
        environment = {
          ...target.environmentFor(types.single as ClassType),
          ...environment,
        };
      }
    }
    var failedCheck = false;
    if (target.covariantParameters.isNotEmpty) {
      arguments = [...arguments];
      for (final index in target.covariantParameters) {
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
        target.returnType,
        effects: effects,
      );
    }
    _Activation? recursive;
    for (
      _Activation? ancestor = caller;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor.body.target == target) {
        recursive = ancestor;
        break;
      }
    }
    final callee =
        recursive ??
        _calls.putIfAbsent((
          caller,
          operation,
          target,
        ), () => _Activation(body, caller));
    final repeated =
        recursive != null ||
        caller.repeated ||
        _loopBlocks(caller.body).contains(block);
    if (repeated && !callee.repeated) {
      callee.repeated = true;
      _pending.add(callee);
    }
    if (recursive != null) {
      for (_Activation? cycle = caller; cycle != null; cycle = cycle.parent) {
        cycle.recursive = true;
        if (!cycle.repeated) {
          cycle.repeated = true;
          _pending.add(cycle);
        }
        if (identical(cycle, recursive)) break;
      }
    }
    if (callee.mergeEnvironment(environment)) _pending.add(callee);
    caller.calls.putIfAbsent(operation, () => {}).add(callee);
    callee.readers.add(caller);
    _supply(callee, arguments, input);
    final invoked = FlowResult(
      value: callee.returned,
      normal: callee.normal?.copy(),
      exceptional: callee.exceptional?.copy(),
      exception: callee.exception,
      stackTrace: callee.stackTrace,
    );
    return failedCheck
        ? _joinResult(invoked, FlowResult(exceptional: input.copy()))
        : invoked;
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
    final incoming = <Block, FlowState>{body.entry: activation.input!.copy()};
    final pending = <Block>{body.entry};
    for (final (index, parameter) in body.entry.parameters.indexed) {
      activation.mergeValue(
        parameter,
        activation.arguments[index].withSource(parameter, activation),
      );
    }
    var summaryChanged = false;

    FlowValue read(Value value) => switch (value) {
      Constant() => FlowValue.constant(value),
      TestedValue(:final test) => read(test.operand),
      UnwindValue() => FlowValue.unknown(value.type),
      _ => activation.values[value] ?? const FlowValue.bottom(),
    };
    void edge(
      Jump jump,
      FlowState state, {
      FlowValue? exception,
      FlowValue? stackTrace,
    }) {
      activation.edges.add(jump);
      activation.mergePoint(activation.edgeStates, jump, state);
      var changed = false;
      for (final (index, parameter) in jump.target.parameters.indexed) {
        changed =
            activation.mergeValue(
              parameter,
              (switch (jump.arguments[index]) {
                UnwindValue.exception =>
                  exception ?? FlowValue.unknown(.object),
                UnwindValue.stackTrace =>
                  stackTrace ?? FlowValue.unknown(.stackTrace),
                final argument => read(argument),
              }).withSource(parameter, activation),
            ) ||
            changed;
      }
      if (incoming[jump.target] case final previous?) {
        changed = previous.join(state) || changed;
      } else {
        incoming[jump.target] = state.copy();
        changed = true;
      }
      if (changed) pending.add(jump.target);
    }

    void exceptional(
      FlowState state,
      FlowValue exception,
      FlowValue stackTrace,
    ) {
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
        summaryChanged = activation.exceptional!.join(state) || summaryChanged;
      }
    }

    while (pending.isNotEmpty) {
      final block = pending.first;
      pending.remove(block);
      activation.blocks.add(block);
      FlowState? state = incoming[block]!.copy();
      FlowResult evaluate(Instruction operation) {
        activation.mergePoint(activation.before, operation, state!);
        final result = _operation(
          activation,
          block,
          operation,
          operation.inputs.map(read).toList(),
          state,
          read,
        );
        activation.mergeValue(
          operation,
          result.value.withSource(operation, activation),
        );
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
          if (_escapingActivations.contains(activation) ||
              (_escapingReturns.contains(body.target) &&
                  identical(_roots[body.target], activation))) {
            state.escape([returned]);
            _admitEscaped(state);
          }
          final joined = activation.returned.join(returned);
          summaryChanged |= joined != activation.returned;
          activation.returned = joined;
          if (activation.normal == null) {
            activation.normal = state.copy();
            summaryChanged = true;
          } else {
            summaryChanged = activation.normal!.join(state) || summaryChanged;
          }
        case final Jump jump:
          edge(jump, state);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final value = read(condition);
          if (value.isBottom) break;
          if (value.constant case ScalarConstant(value: final bool known)) {
            edge(known ? ifTrue : ifFalse, state);
          } else {
            edge(ifTrue, state);
            edge(ifFalse, state);
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
    if (_escapingActivations.contains(activation) ||
        (_escapingReturns.contains(body.target) &&
            identical(_roots[body.target], activation))) {
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
      allocate: allocate,
      repeated: repeated,
      invoke: invoke,
      call: call,
    );
    if (stored != null) {
      activation.operationEffects[operation] = {
        ...stored.effects,
        if (stored.exceptional != null) Effect.mayThrow,
      };
      return stored;
    }
    switch (operation) {
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
        );
      case BindMethod(:final method, :final receiver, :final direct):
        final next = state.copy();
        var value = const FlowValue.bottom();
        var mayFail = false;
        var found = false;
        for (final type in _receiverTypes(read(receiver))) {
          found = true;
          final target = direct
              ? method
              : program.lookupMember(type, method.selector).target;
          if (target == null) {
            value = value.join(FlowValue.unknown(operation.type));
            mayFail = true;
            continue;
          }
          final actual = target.reifiedSignature.substitute(
            target.environmentFor(type),
          );
          final expected = operation.type.substitute(activation.environment);
          final unresolved =
              actual.freeTypeParameters.isNotEmpty ||
              expected.freeTypeParameters.isNotEmpty;
          if (!unresolved && !expected.accepts(actual)) {
            mayFail = true;
            continue;
          }
          mayFail |= unresolved;
          final object = FlowObject(
            operation,
            activation,
            type: actual,
            variant: target,
          );
          next.retain(object, [
            read(receiver).check(type).value,
          ], repeated: repeated);
          activation.boundMethods.putIfAbsent(object, () => {}).add(target);
          value = value.join(FlowValue.object(object));
        }
        if (!found) {
          value = value.join(FlowValue.unknown(operation.type));
          mayFail = true;
        }
        activation.operationEffects[operation] = {
          if (!value.isBottom) Effect.allocates,
          if (mayFail) Effect.mayThrow,
        };
        return FlowResult(
          value: value,
          normal: value.isBottom ? null : next,
          exceptional: mayFail ? state.copy() : null,
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
      case NativeCallbackAddress(:final function):
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: FlowValue.unknown(.integer)
              .withReferences([FlowValue.constant(FunctionConstant(function))]),
          normal: state.copy(),
        );
      case NativeClosureEntryAddress(:final lookup):
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: FlowValue.unknown(.integer)
              .withReferences([FlowValue.constant(FunctionConstant(lookup))]),
          normal: state.copy(),
        );
      case ReferenceAddress():
        activation.operationEffects[operation] = const {Effect.readsStorage};
        return FlowResult(
          value: FlowValue.unknown(.integer).withReferences(inputs),
          normal: state.copy(),
        );
      case ReferenceFromAddress():
        var value = FlowValue.unknown(operation.type)
            .withReferences(inputs.map((value) => value.references));
        for (final source in inputs.single.sources) {
          if (source.value case ReferenceAddress(:final object)
              when source.activation is _Activation) {
            final creator = source.activation as _Activation;
            value = object is Constant
                ? FlowValue.constant(object)
                : creator.values[object] ?? value;
            break;
          }
        }
        activation.operationEffects[operation] = const {Effect.readsStorage};
        return FlowResult(value: value, normal: state.copy());
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
      case TypeCast():
        final checked = inputs.single.check(
          operation.type.substitute(activation.environment),
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
        if (inputs.single.constant != null) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: inputs.single,
            normal: state.copy(),
            exceptional: null,
          );
        }
        activation.operationEffects[operation] = operation.effects;
        return FlowResult(
          value: inputs.single,
          normal: state.copy(),
          exceptional: operation.mayThrow ? state.copy() : null,
        );
      case NullCheck():
        final known = inputs.single.constant;
        activation.operationEffects[operation] = operation.effects;
        if (known case ScalarConstant(value: null)) {
          return FlowResult(
            value: const FlowValue.bottom(),
            normal: null,
            exceptional: state.copy(),
          );
        }
        return FlowResult(
          value: inputs.single,
          normal: state.copy(),
          exceptional: inputs.single.types.every((type) => !type.mayBeNull)
              ? null
              : state.copy(),
        );
      default:
        final folded = _fold(operation, inputs);
        if (folded != null) {
          activation.operationEffects[operation] = const {};
          return FlowResult(
            value: FlowValue.constant(folded),
            normal: state.copy(),
            exceptional: null,
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
            operation.type,
          );
        }
        final next = state.copy();
        if (operation.effects.contains(Effect.writesStorage)) {
          next.invalidate(inputs);
        }
        return FlowResult(
          value: operation.type == .never
              ? const FlowValue.bottom()
              : FlowValue.unknown(operation.type)
                    .withReferences(inputs.map((value) => value.references)),
          normal: operation.type == .never ? null : next,
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
    FlowState state,
  ) {
    var result = _unreachable;
    var unresolved = false;
    var found = false;
    for (final type in _receiverTypes(receiver)) {
      found = true;
      final lookup = program.lookupMember(type, selector);
      final target = lookup.target;
      if (target == null || lookup.unsupportedForwarder) {
        unresolved = true;
        continue;
      }
      final body = program.implementationOf(target);
      if (body == null) {
        unresolved = true;
        continue;
      }
      if (!target.signature.acceptsShape(positional.length, named.keys)) {
        unresolved = true;
        continue;
      }
      final arguments = target.signature.bind<FlowValue>(
        positional,
        named,
        (index) => FlowValue.constant(body.defaults[index]!),
      );
      final invoked = _invoke(
        activation,
        block,
        operation,
        target,
        [receiver, ...arguments],
        state,
        environment: _environment(target, type, typeArguments, activation),
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
          operation.type,
        ),
      );
    }
    return result;
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
  }) {
    FlowResult result = _unreachable;
    final appliedArguments = [
      for (final type
          in typeArguments ??
              (site is FunctionCall ? site.typeArguments : const <ValueType>[]))
        type.substitute(activation.environment),
    ];
    for (final constant in function.constants.whereType<FunctionConstant>()) {
      var target = constant.target;
      var signature = constant.type as FunctionType;
      if (signature.typeParameters.isNotEmpty) {
        signature = signature.instantiate(appliedArguments);
      }
      var owner = constant.ownerType;
      var genericArguments = constant.typeArguments ?? appliedArguments;
      if (constant.constructorTypeArguments case final template?) {
        genericArguments = [
          for (final type in template)
            type.substitute({
              for (final (index, parameter)
                  in constant.constructorSignature!.typeParameters.indexed)
                parameter: genericArguments[index],
            }),
        ];
      }
      if (target.kind == .initializer || target.kind == .factory) {
        final resolved = target.resolveConstruction(
          signature.result as ClassType,
        );
        target = resolved.target;
        owner = resolved.ownerType;
        genericArguments = const [];
      }
      target = target.implementation;
      final body = program.implementationOf(target);
      final arguments = target.signature.bind<FlowValue>(
        positional,
        named,
        (index) => FlowValue.constant(body!.defaults[index]!),
      );
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
          FlowObject(site, activation, type: owner!),
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
        );
      }
      result = _joinResult(result, invoked);
    }
    for (final object in function.objects) {
      final captures = state.capturesOf(object);
      if (captures == null) {
        activation.unknownCalls.add(site);
        continue;
      }
      switch (object.site) {
        case InstantiateFunction() || InstantiateFunctionFrom():
          final creator = object.activation as _Activation;
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
              typeArguments: creator.instantiations[object]!,
            ),
          );
        case MakeClosure(:final target):
          final body = program.implementationOf(target)!;
          final arguments = target.signature.bind<FlowValue>(
            positional,
            named,
            (index) => FlowValue.constant(body.defaults[index]!),
          );
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
                ...(object.activation as _Activation).environment,
                ..._environment(target, null, appliedArguments, activation),
              },
            ),
          );
        case BindMethod():
          final creator = object.activation as _Activation;
          for (final target
              in creator.boundMethods[object] ?? <FunctionTarget>{}) {
            final body = program.implementationOf(target)!;
            final arguments = target.signature.bind<FlowValue>(
              positional,
              named,
              (index) => FlowValue.constant(body.defaults[index]!),
            );
            result = _joinResult(
              result,
              _invoke(activation, block, site, target, [
                ...captures,
                ...arguments,
              ], state),
            );
          }
        default:
          activation.unknownCalls.add(site);
      }
    }
    if (function.unknownTypes.isNotEmpty ||
        activation.unknownCalls.contains(site)) {
      activation.unknownCalls.add(site);
      result = _joinResult(
        result,
        _external(
          activation,
          block,
          site,
          [function, ...positional, ...named.values],
          state,
          site.type,
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
    final reachable = next.escape([...inputs, state.escapedValues]);
    if (effects.contains(Effect.writesStorage)) next.invalidate([reachable]);
    if (effects.contains(Effect.callsUserCode)) {
      // Re-entry follows values that crossed this boundary or declared exports.
      _admitEscaped(next);
      for (final target in _openEntries) {
        final callback = _roots[target]!;
        callback.readers.add(activation);
        _supply(callback, callback.arguments, next);
      }
      for (final callback in {
        ..._escapingActivations,
        for (final target in _openEntries) _roots[target]!,
      }) {
        callback.readers.add(activation);
        _supply(callback, callback.arguments, next);
        if (callback.normal != null) next.join(callback.normal!);
        if (callback.exceptional != null) next.join(callback.exceptional!);
      }
    }
    return FlowResult(
      value: resultType == .never
          ? const FlowValue.bottom()
          : FlowValue.unknown(resultType).withReferences([reachable]),
      normal: resultType == .never ? null : next,
      exceptional: effects.contains(Effect.mayThrow) ? next.copy() : null,
    );
  }

  void _publishExternal(FlowState state) {
    final changed = _externalState == null ? true : _externalState!.join(state);
    _externalState ??= state.copy();
    if (!changed) return;
    for (final callback in {
      ..._escapingActivations,
      for (final target in _openEntries) _roots[target]!,
    }) {
      _supply(callback, callback.arguments, _externalState!);
    }
  }

  void _admitEscaped(FlowState state) {
    final reachable = state.escapedValues;
    void admit(
      Object key,
      FunctionTarget target,
      List<FlowValue> arguments, {
      Map<TypeParameterType, ValueType> environment = const {},
    }) {
      final body = program.implementationOf(target);
      if (body is! IrFunction) return;
      final activation = _escapedCalls.putIfAbsent(
        key,
        () => _Activation(body, null),
      );
      activation.repeated = true;
      _escapingActivations.add(activation);
      activation.mergeEnvironment(environment);
      _supply(activation, arguments, state);
    }

    for (final constant in reachable.constants.whereType<FunctionConstant>()) {
      final target = constant.target.implementation;
      admit(
        constant.structuralKey,
        target,
        target.parameterTypes.map(FlowValue.unknown).toList(),
        environment: {
          if (constant.ownerType != null)
            ...target.environmentFor(constant.ownerType!),
          for (final (i, type)
              in (constant.typeArguments ?? const <ValueType>[]).indexed)
            if (i < target.typeParameters.length)
              target.typeParameters[i]: type,
        },
      );
    }
    for (final object in reachable.objects) {
      if (object.site case MakeClosure(:final target)) {
        final captures = state.capturesOf(object);
        if (captures != null) {
          admit(object, target, [
            FlowValue.object(object),
            ...captures,
            ...target.signature.parameters.map(FlowValue.unknown),
          ], environment: (object.activation as _Activation).environment);
        }
      } else if (object.site is BindMethod) {
        final creator = object.activation as _Activation;
        for (final target
            in creator.boundMethods[object] ?? <FunctionTarget>{}) {
          final captures = state.capturesOf(object);
          if (captures != null) {
            admit(
              (object, target),
              target,
              [
                ...captures,
                ...target.signature.parameters.map(FlowValue.unknown),
              ],
            );
          }
        }
      }
    }
  }

  Iterable<ClassType> _receiverTypes(FlowValue value) sync* {
    final seen = <ClassType>{};
    for (final type in [
      ...value.constants.map((constant) => constant.type),
      ...value.objects.map((object) => object.type),
    ]) {
      if (type is ClassType && seen.add(type)) yield type;
    }
    for (final bound in value.unknownTypes) {
      for (final declaration in program.classes) {
        final type = declaration.type;
        if (!type.isAbstract && bound.mayHaveInstance(type) && seen.add(type)) {
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
      return valueOf(value.test.operand, activation: activation);
    }
    var result = const FlowValue.bottom();
    for (final item in _at(value, activation)) {
      result = result.join(item.values[value] ?? const FlowValue.bottom());
    }
    return result;
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
    if (!exits.normal ||
        exits.exceptional ||
        effectsOf(
          operation,
          activation: activation,
        ).any((effect) => effect != .readsStorage && effect != .allocates)) {
      return false;
    }
    for (final item in _at(operation, activation)) {
      if (item.unknownCalls.contains(operation) ||
          item.externalCalls.contains(operation)) {
        return false;
      }
      for (final callee in item.calls[operation] ?? <_Activation>{}) {
        if (!_terminates(callee, {})) return false;
      }
    }
    return true;
  }

  bool _terminates(_Activation activation, Set<_Activation> visiting) {
    if (!visiting.add(activation) ||
        activation.recursive ||
        activation.body is! IrFunction ||
        activation.normal == null) {
      return false;
    }
    final body = activation.body as IrFunction;
    if (body.bodyKind != .synchronous ||
        _cyclicBlocks(body.blocks, edges: activation.edges).isNotEmpty ||
        activation.unknownCalls.isNotEmpty ||
        activation.externalCalls.isNotEmpty) {
      return false;
    }
    for (final callees in activation.calls.values) {
      for (final callee in callees) {
        if (!_terminates(callee, visiting)) return false;
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

final class _Activation(final IrCallable body, final _Activation? parent) {
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

  bool mergeValue(Value value, FlowValue incoming) {
    final previous = values[value] ?? const FlowValue.bottom();
    final joined = previous.join(incoming);
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

Constant? _fold(Instruction operation, List<FlowValue> inputs) {
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
          .lessThan => left < right,
          .lessOrEqual => left <= right,
          .greaterThan => left > right,
          .greaterOrEqual => left >= right,
        };
      case NumericNegate():
        result = -(scalars.single as num);
      case NumericToDouble():
        result = (scalars.single as num).toDouble();
      case Equals(:final negated)
          when constants.every((value) => value is ScalarConstant):
        result = (scalars[0] == scalars[1]) != negated;
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
    _ => null,
  };
}
