import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final class FixtureRunner(
  List<IrFunction> functions,
  final Map<(Uri, String), Object? Function(int)> imports,
) {
  final bodies = {for (final f in functions) f.target: f};

  Object? run(IrFunction function, List<Object?> args) {
    final values = <Value, Object?>{};
    Object? read(Value v) => switch (v) {
      ScalarConstant(:final value) => value,
      RecordConstant(:final type, :final fields) => _RecordValue(
        type as RecordType,
        fields.map(read).toList(),
      ),
      TestedValue(:final test) => read(test.operand),
      _ => values[v],
    };
    void execute(Instruction op) {
      switch (op) {
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
            .lessThan => a < b,
            .lessOrEqual => a <= b,
            .greaterThan => a > b,
            .greaterOrEqual => a >= b,
          };
        case Equals(:final left, :final right, :final negated):
          values[op] = (read(left) == read(right)) != negated;
        case DirectCall(:final target, :final inputs):
          final arguments = inputs.map(read).toList();
          values[op] = bodies.containsKey(target)
              ? run(bodies[target]!, arguments)
              : imports[(target.library, target.name)]!(
                  arguments.single as int,
                );
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
    ValueType.error => scalar<Error>(),
    ValueType.typeError => scalar<TypeError>(),
    ValueType.stackTrace => scalar<StackTrace>(),
    ValueType.never => run<Never>(),
    ValueType.voidType => cast ? value : true,
    _ => throw StateError('Unexpected fixture type ${type.dartName}'),
  };
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
