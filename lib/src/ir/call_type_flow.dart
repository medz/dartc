import 'block.dart';
import 'function.dart';
import 'program.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// A call closure narrowed by the union of values passed to each parameter.
///
/// The roots and unknownCalls arguments add entry points admitting every value
/// of their declared parameter types.
/// Function values, closures and implicit calls also keep unknown arguments.
/// Storage reads retain their static types; this analysis never rewrites IR or
/// replaces its validation, argument checks, effects or exception edges.
///
/// Code generation must repeat the analysis when generated calls add source
/// dependencies, including calls to an already selected function. Such targets
/// belong among unknown callers unless their actual arguments are analyzed here.
final class CallTypeFlow(
  final IrProgram program,
  Iterable<FunctionTarget> roots, {
  Iterable<ClassType> instantiatedTypes = const [],
  Iterable<FunctionTarget> unknownCalls = const [],
}) {
  final _definitions = <FunctionTarget>{};
  final _pending = <FunctionTarget>{};
  final _virtuals = <FunctionTarget>{};
  final _instances = <ClassType>{};
  final _parameters = <BlockParameter, Set<ValueType>>{};
  final _returns = <FunctionTarget, Set<ValueType>>{};
  final _callers = <FunctionTarget, Set<FunctionTarget>>{};
  final _targets = <InstanceCall, Set<FunctionTarget>>{};
  final _directCalls = <DirectCall>{};

  /// The source bodies and imports required by the analyzed entry points.
  late final Set<FunctionTarget> definitions = .unmodifiable(_definitions);

  this {
    _instances.addAll(instantiatedTypes.map((type) => type.declaration));
    for (final target in [...roots, ...unknownCalls]) {
      _include(target, unknown: true);
    }
    while (_pending.isNotEmpty) {
      final target = _pending.first;
      _pending.remove(target);
      _visit(target);
    }
  }

  /// Whether [receiver] can hold an instance of [actual] at any observed call.
  ///
  /// Values outside the analyzed source graphs retain their static bounds.
  bool allows(Value receiver, ClassType actual) =>
      receiver.unviewedType.mayHaveInstance(actual) &&
      _types(receiver).any((type) => type.mayHaveInstance(actual));

  Iterable<ValueType> _types(Value value) => switch (value) {
    TypeView(:final operand) ||
    TypeCast(:final operand) ||
    UncheckedCast(:final operand) ||
    NullCheck(:final operand) => _types(operand),
    TestedValue(:final test) => _types(test.operand),
    BlockParameter() => _parameters[value] ?? [value.type],
    DirectCall(:final target) when _directCalls.contains(value) => _result(
      target,
      value.type,
    ),
    InstanceCall() when _targets.containsKey(value) => _targets[value]!.expand(
      (target) => _result(target, value.type),
    ),
    _ => [value.type],
  };

  Iterable<ValueType> _result(FunctionTarget target, ValueType fallback) =>
      switch (program.implementationOf(target)) {
        IrFunction(bodyKind: FunctionBodyKind.synchronous) =>
          _returns[target] ?? const [],
        _ => [fallback],
      };

  bool _merge(Set<ValueType> into, Iterable<ValueType> types) {
    final before = into.length;
    into.addAll(types.toList());
    return into.length != before;
  }

  void _include(FunctionTarget target, {bool unknown = false}) {
    target = target.implementation;
    final body = program.implementationOf(target);
    if (_definitions.add(target)) {
      _pending.add(target);
      if (body is IrFunction) {
        for (final block in body.blocks) {
          for (final parameter in block.parameters) {
            _parameters[parameter] = {};
          }
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            if (operation is DirectCall) _directCalls.add(operation);
            if (operation is InstanceCall) _targets[operation] = {};
          }
        }
      }
      final before = _instances.length;
      _instances.addAll([
        ...?body?.instantiatedClasses,
        if (body != null && body.recordTypes.isNotEmpty)
          for (final declaration in program.classes)
            if (declaration.recordStorage) declaration.type,
      ]);
      if (before != _instances.length) _pending.addAll(_virtuals);
    }
    if (unknown && body is IrFunction) {
      for (final parameter in body.entry.parameters) {
        if (_parameters[parameter]!.add(parameter.type)) _pending.add(target);
      }
    }
  }

  void _invoke(
    FunctionTarget caller,
    FunctionTarget target,
    List<Value> arguments,
  ) {
    _include(target);
    (_callers[target] ??= {}).add(caller);
    final body = program.implementationOf(target);
    if (body is! IrFunction) return;
    for (final (i, parameter) in body.entry.parameters.indexed) {
      if (_merge(_parameters[parameter]!, _types(arguments[i]))) {
        _pending.add(target);
      }
    }
  }

  Iterable<FunctionTarget> _members(
    FunctionTarget caller,
    Value receiver,
    Iterable<MemberSelector> selectors, {
    bool bound = false,
  }) sync* {
    _virtuals.add(caller);
    // Selecting a member can discover more instances while this loop is active.
    for (final type in _instances.toList()) {
      if (bound
          ? !receiver.unviewedType.mayHaveInstance(type)
          : !allows(receiver, type)) {
        continue;
      }
      for (final selector in selectors) {
        if (program.lookupMember(type, selector).target case final target?) {
          yield target;
        }
      }
    }
  }

  void _visit(FunctionTarget target) {
    final body = program.implementationOf(target);
    if (body == null) return;
    for (final value in body.functionConstants) {
      _include(value.target, unknown: true);
    }
    if (body is! IrFunction) return;
    for (final closure in body.closures) {
      _include(closure, unknown: true);
    }
    for (final global in body.globals) {
      if (global.initializer case final initializer?) {
        _include(initializer, unknown: true);
      }
    }
    for (final block in body.blocks) {
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        switch (operation) {
          case DirectCall(:final target, :final inputs):
            _invoke(body.target, target, inputs);
          case Construct(:final initializer, :final inputs):
            _invoke(target, initializer, [operation, ...inputs]);
          case InstanceCall(:final receiver, :final member):
            final targets = _targets[operation]!;
            for (final selected in _members(target, receiver, [
              member.selector,
            ])) {
              targets.add(selected);
              final definition = program.implementationOf(selected);
              if (definition == null) {
                _include(selected);
                continue;
              }
              _invoke(target, selected, [
                receiver,
                ...selected.signature.bind<Value>(
                  operation.positional,
                  operation.named,
                  (index) => definition.defaults[index]!,
                ),
              ]);
            }
          case BindMethod(:final method, :final receiver, :final direct):
            for (final selected
                in direct
                    ? [method]
                    : _members(target, receiver, [
                        method.selector,
                      ], bound: true)) {
              _include(selected, unknown: true);
            }
          case DynamicDispatch(:final receiver, :final selector):
            for (final selected in _members(target, receiver, [
              selector,
              if (selector.kind == .getter || selector.kind == .method)
                (
                  kind: selector.kind == .getter
                      ? FunctionKind.method
                      : FunctionKind.getter,
                  name: selector.name,
                  privateScope: selector.privateScope,
                ),
              (
                kind: FunctionKind.method,
                name: 'noSuchMethod',
                privateScope: null,
              ),
              (kind: FunctionKind.method, name: 'call', privateScope: null),
            ])) {
              _include(selected, unknown: true);
            }
          case NativeCallbackAddress(:final function):
            _include(function, unknown: true);
          case NativeClosureEntryAddress(:final lookup):
            _include(lookup, unknown: true);
          case LoadField(field: InstanceField(:final initializer?)):
            _include(initializer, unknown: true);
          default:
            if (operation.implicitMember case final member?) {
              for (final selected in _members(target, operation.inputs.first, [
                member.selector,
              ])) {
                _include(selected, unknown: true);
              }
            }
        }
      }
      for (final edge in block.successors) {
        for (final (i, parameter) in edge.target.parameters.indexed) {
          if (_merge(_parameters[parameter]!, _types(edge.arguments[i]))) {
            _pending.add(target);
          }
        }
      }
      if (block.end case Return(:final value)
          when body.bodyKind == .synchronous) {
        if (_merge(
          _returns[target] ??= {},
          value == null ? [.nullType] : _types(value),
        )) {
          _pending.addAll(_callers[target] ?? const []);
        }
      }
    }
  }
}
