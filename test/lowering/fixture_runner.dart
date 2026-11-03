import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final class FixtureRunner(
  final IrProgram program,
  final Map<(Uri, String), Object? Function(int)> imports,
) {
  final bodies = {for (final f in program.functions) f.target: f};

  final _staticFunctions = <FunctionTarget, _FunctionValue>{};

  Object? _constant(Constant value) => switch (value) {
    ScalarConstant(:final value) => value,
    FunctionConstant(:final target) => _staticFunctions.putIfAbsent(
      target,
      () => _FunctionValue(target),
    ),
    RecordConstant(:final type, :final fields) => _RecordValue(
      type as RecordType,
      fields.map(_constant).toList(),
    ),
  };

  Object? _enter(FunctionTarget target, List<Object?> arguments) {
    final body = bodies[target];
    return body != null
        ? run(body, arguments)
        : imports[(target.library, target.name)]!(arguments.single as int);
  }

  _Instance _construct(FunctionTarget init, List<Object?> arguments) {
    final instance = _Instance(init.owner!, this);
    if (init.owner != ValueType.object) _enter(init, [instance, ...arguments]);
    return instance;
  }

  Object? _invoke(
    _FunctionValue fn,
    List<Object?> positional,
    Map<String, Object?> named,
  ) {
    final target = fn.target.implementation;
    final arguments = target.signature.bind<Object?>(
      positional,
      named,
      (i) => _constant(bodies[target]!.defaults[i]!),
    );
    for (final (i, arg) in arguments.indexed) {
      _typeOperation(target.signature.parameters[i], arg, cast: true);
    }
    return target.kind == .initializer
        ? _construct(target, arguments)
        : _enter(target, [?fn.receiver, ...arguments]);
  }

  Object? run(IrFunction function, List<Object?> args) {
    final values = <Value, Object?>{};
    Object? read(Value v) => switch (v) {
      Constant() => _constant(v),
      TestedValue(:final test) => read(test.operand),
      _ => values[v],
    };
    void execute(Instruction op) {
      switch (op) {
        case Construct(:final initializer, :final inputs):
          values[op] = _construct(initializer, inputs.map(read).toList());
        case BindMethod(:final method, :final receiver, :final direct):
          final instance = read(receiver) as _Instance;
          values[op] = _FunctionValue(
            direct ? method : program.dispatch(instance.type, method)!,
            instance,
          );
        case FunctionCall(:final function, :final positional, :final named):
          values[op] = _invoke(
            read(function) as _FunctionValue,
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
          );
        case StoreField(:final field, :final receiver, :final value):
          (read(receiver) as _Instance).fields[field] = read(value);
        case LoadField(:final field, :final receiver):
          values[op] = (read(receiver) as _Instance).fields[field];
        case InstanceCall(
          :final member,
          :final receiver,
          :final positional,
          :final named,
        ):
          final instance = read(receiver) as _Instance;
          final target = program.dispatch(instance.type, member)!;
          values[op] = _invoke(
            _FunctionValue(target, instance),
            positional.map(read).toList(),
            {for (final e in named.entries) e.key: read(e.value)},
          );
        case MakeRecord(:final type, :final inputs):
          values[op] = _RecordValue(
            type as RecordType,
            inputs.map(read).toList(),
          );
        case RecordGet(:final record, :final slot):
          values[op] = (read(record) as _RecordValue).fields[slot];
        case TypeTest(:final operand, :final testedType, :final negated):
          values[op] =
              (_typeOperation(testedType, read(operand), cast: false)
                  as bool) !=
              negated;
        case TypeCast(:final operand, :final type):
          values[op] = _typeOperation(type, read(operand), cast: true);
        case NullCheck(:final operand):
          values[op] = read(operand)!;
        case IntBinary(:final operator, :final left, :final right):
          final a = read(left) as int, b = read(right) as int;
          values[op] = switch (operator) {
            .add => a + b,
            .subtract => a - b,
            .multiply => a * b,
            .divide => a / b,
            .truncateDivide => a ~/ b,
            .modulo => a % b,
            .bitAnd => a & b,
            .bitOr => a | b,
            .bitXor => a ^ b,
            .shiftLeft => a << b,
            .shiftRight => a >> b,
            .unsignedShiftRight => a >>> b,
            .lessThan => a < b,
            .lessOrEqual => a <= b,
            .greaterThan => a > b,
            .greaterOrEqual => a >= b,
          };
        case Equals(:final left, :final right, :final negated):
          values[op] = (read(left) == read(right)) != negated;
        case DirectCall(:final target, :final inputs):
          final arguments = inputs.map(read).toList();
          values[op] = _enter(target, arguments);
      }
    }

    var block = function.entry;
    for (var steps = 0; steps < 1000; steps++) {
      for (final (i, p) in block.parameters.indexed) {
        values[p] = args[i];
      }
      block.instructions.forEach(execute);
      final end = block.end;
      Jump? edge;
      Jump? handler;
      try {
        switch (end) {
          case Return(:final value):
            return value == null ? null : read(value);
          case Invoke(:final operation, :final onReturn, :final onThrow):
            handler = onThrow;
            execute(operation);
            edge = onReturn;
          case Throw(:final exception, :final stackTrace, :final onThrow):
            handler = onThrow;
            final error = read(exception)!;
            if (stackTrace != null) {
              Error.throwWithStackTrace(error, read(stackTrace) as StackTrace);
            }
            throw error;
          case Unreachable():
            fail('Reached a Never continuation');
          case ExhaustivenessFailure():
            fail('Exhaustive fixture had no matching case');
          case Jump():
            edge = end;
          case Branch():
            edge = read(end.condition) as bool ? end.ifTrue : end.ifFalse;
        }
      } catch (exception, trace) {
        if (handler == null) rethrow;
        values[UnwindValue.exception] = exception;
        values[UnwindValue.stackTrace] = trace;
        edge = handler;
      }
      if (edge == null) fail('A Never operation returned');
      args = edge.arguments.map(read).toList();
      block = edge.target;
    }
    fail(
      'Fixture did not return in 1000 block visits: ${function.target.name}',
    );
  }
}

Object? _typeOperation(ValueType type, Object? value, {required bool cast}) {
  Object? run<T>() => cast ? value as T : value is T;
  Object? scalar<T>() => type == type.nonNullable ? run<T>() : run<T?>();
  final actual = switch (value) {
    _Instance(:final type) => type,
    _FunctionValue(:final target) => target.reifiedSignature,
    _ => null,
  };
  if (actual != null || type.nonNullable is FunctionType) {
    final ok = actual != null
        ? type.accepts(actual)
        : value == null && type.accepts(.nullType);
    if (!cast) return ok;
    if (!ok) throw TypeError();
    return value;
  }
  if (type.nonNullable case final RecordType target) {
    final ok = value == null
        ? type.accepts(.nullType)
        : value is _RecordValue &&
              target.sameShape(value.type) &&
              target.fields.indexed.every(
                (p) =>
                    _typeOperation(p.$2, value.fields[p.$1], cast: false)
                        as bool,
              );
    if (!cast) return ok;
    if (ok) return value;
    throw TypeError();
  }
  if (type.nonNullable == .record) {
    final ok =
        value is _RecordValue ||
        value is Record ||
        (value == null && type.accepts(.nullType));
    if (!cast) return ok;
    if (ok) return value;
    throw TypeError();
  }
  if (type == .nullType) return run<Null>();
  return switch (type.nonNullable) {
    ValueType.integer => scalar<int>(),
    ValueType.floating => scalar<double>(),
    ValueType.number => scalar<num>(),
    ValueType.string => scalar<String>(),
    ValueType.boolean => scalar<bool>(),
    ValueType.object => scalar<Object>(),
    ValueType.function => scalar<Function>(),
    ValueType.error => scalar<Error>(),
    ValueType.typeError => scalar<TypeError>(),
    ValueType.stackTrace => scalar<StackTrace>(),
    ValueType.never => run<Never>(),
    ValueType.voidType => cast ? value : true,
    ClassType() =>
      cast
          ? (value == null && type.accepts(.nullType)
                ? null
                : throw TypeError())
          : value == null && type.accepts(.nullType),
    _ => throw StateError('Unexpected fixture type ${type.dartName}'),
  };
}

final class _FunctionValue(
  final FunctionTarget target, [
  final _Instance? receiver,
]) {
  @override
  bool operator ==(Object other) =>
      other is _FunctionValue &&
      target == other.target &&
      identical(receiver, other.receiver);
  @override
  int get hashCode => Object.hash(target, identityHashCode(receiver));
}

final class _Instance(final ClassType type, final FixtureRunner runner) {
  final fields = <InstanceField, Object?>{};

  static final _equality = FunctionTarget(
    ValueType.object.library,
    '==',
    .boolean,
    [.object],
    owner: ValueType.object,
    kind: .method,
  );

  @override
  bool operator ==(Object other) {
    final target = runner.program.dispatch(type, _equality);
    return target == null
        ? identical(this, other)
        : runner._invoke(_FunctionValue(target, this), [other], const {})
              as bool;
  }

  @override
  int get hashCode => identityHashCode(this);
}

final class _RecordValue(final RecordType type, final List<Object?> fields) {
  @override
  bool operator ==(Object other) =>
      other is _RecordValue &&
      type.sameShape(other.type) &&
      fields.indexed.every((p) => p.$2 == other.fields[p.$1]);

  @override
  int get hashCode => Object.hashAll(fields);
}
