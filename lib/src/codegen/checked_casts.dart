import 'package:dartc/ir.dart';

/// Generates checked conversions using ordinary type tests and exception edges.
final class CheckedCasts() {
  static final _uri = Uri.parse('dartc:checks');
  final _error = ClassType(_uri, '_TypeError', superclass: ValueType.typeError);
  late final _initializer = FunctionTarget(
    _uri,
    '_TypeError',
    .voidType,
    [],
    owner: _error,
    kind: .initializer,
  );
  final _checks = <(ValueType, ValueType, bool), IrFunction>{};

  late final classes = [
    IrClass(ValueType.error, []),
    IrClass(ValueType.typeError, []),
    IrClass(_error, [], constructors: [_initializer]),
  ];

  Iterable<IrFunction> get functions sync* {
    if (_checks.isEmpty) return;
    yield IrFunction(_initializer, [
      Block(_initializer.parameterTypes)..finish(const Return()),
    ]);
    yield* _checks.values;
  }

  FunctionTarget targetFor(Instruction instruction) {
    final (operand, nullOnly) = switch (instruction) {
      TypeCast(:final operand) => (operand, false),
      NullCheck(:final operand) => (operand, true),
      _ => throw ArgumentError('Expected a checked conversion.'),
    };
    final source = operand.type, result = instruction.type;
    if (source.freeTypeParameters.isNotEmpty ||
        result.freeTypeParameters.isNotEmpty) {
      throw UnsupportedError(
        'Native cast requires a type environment: $source to $result',
      );
    }
    return _checks.putIfAbsent((source, result, nullOnly), () {
      final target = FunctionTarget(_uri, 'check${_checks.length}', result, [
        source,
      ]);
      final entry = Block(target.parameterTypes), failed = Block();
      final blocks = [entry, failed];
      if (result == .never) {
        entry.finish(Jump(failed));
      } else {
        final operand = entry.parameters.single;
        final test = entry.emit(TypeTest(operand, nullOnly ? .object : result));
        // FutureOr<int?> keeps its static type after a null assertion.
        final accepted = nullOnly && result == source
            ? operand
            : test.refinement(true) ?? operand;
        final done = Block(result == .voidType ? [] : [result]);
        entry.finish(
          Branch(
            test,
            Jump(done, result == .voidType ? [] : [accepted]),
            Jump(failed),
          ),
        );
        done.finish(
          Return(result == .voidType ? null : done.parameters.single),
        );
        blocks.add(done);
      }
      failed.finish(Throw(failed.emit(Construct(_initializer, []))));
      return IrFunction(target, blocks);
    }).target;
  }
}
