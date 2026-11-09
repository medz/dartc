import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('assertion failure terminates and cannot expose compiler storage', () {
    final failure = AssertionFailure(const Constant.string('failed'));
    expect(failure.type, ValueType.never);
    expect(failure.mayThrow, isTrue);
    expect(failure.inputs, [const Constant.string('failed')]);
    expect(AssertionFailure(null).inputs, isEmpty);
    expect(
      () => AssertionFailure(NewCell(CellType(ValueType.integer), null)),
      throwsArgumentError,
    );
    expect(ValueType.error.accepts(ValueType.assertionError), isTrue);
    expect(ValueType.typeError.accepts(ValueType.assertionError), isFalse);
  });

  test(
    'deferred storage has no fabricated initializer and copies preserve type',
    () {
      final slot = NewCell(CellType(ValueType.integer), null);
      expect(slot.inputs, isEmpty);
      final copy = CopyCell(slot);
      expect(copy.type, slot.type);
      expect(copy.inputs, [slot]);
      expect(copy.mayThrow, isTrue);
      expect(ReadCell(copy).type, ValueType.integer);
      expect(() => CopyCell(const Constant.integer(1)), throwsArgumentError);
      expect(
        () => NewCell(CellType(ValueType.integer), const Constant.nullValue()),
        throwsArgumentError,
      );
      expect(
        () => WriteCell(slot, const Constant.string('wrong')),
        throwsArgumentError,
      );
    },
  );

  test('numeric operations validate operands and retain result precision', () {
    const i = Constant.integer(1), d = Constant.floating(1.5);
    final number = Block([ValueType.number]).parameters.single;
    expect(NumericBinary(.add, i, i).type, ValueType.integer);
    expect(NumericBinary(.add, i, d).type, ValueType.floating);
    expect(NumericBinary(.add, number, i).type, ValueType.number);
    expect(NumericBinary(.divide, i, i).type, ValueType.floating);
    expect(NumericBinary(.truncateDivide, d, number).type, ValueType.integer);
    expect(NumericBinary(.lessThan, i, d).type, ValueType.boolean);
    expect(NumericBinary(.truncateDivide, d, i).mayThrow, isTrue);
    expect(NumericBinary(.modulo, number, i).mayThrow, isTrue);
    expect(NumericBinary(.modulo, d, i).mayThrow, isFalse);
    expect(NumericNegate(number).type, ValueType.number);
    expect(NumericToDouble(number).type, ValueType.floating);
    expect(NumericToDouble(i).effects, isEmpty);
    expect(NumericToDouble(d).inputs, [d]);
    expect(NumericSquareRoot(number).type, ValueType.floating);
    expect(NumericSquareRoot(i).effects, isEmpty);
    expect(NumericSquareRoot(d).inputs, [d]);
    expect(
      () => NumericSquareRoot(const Constant.nullValue()),
      throwsArgumentError,
    );
    expect(
      () => NumericToDouble(const Constant.boolean(false)),
      throwsArgumentError,
    );
    expect(
      () => NumericBinary(.add, i, const Constant.nullValue()),
      throwsArgumentError,
    );
    expect(
      () => NumericNegate(const Constant.string('not a number')),
      throwsArgumentError,
    );
  });

  test(
    'static accessors have distinct identities without receiver parameters',
    () {
      final uri = Uri.parse('memory:accessors');
      final get = FunctionTarget(
        uri,
        'value',
        .integer,
        [],
        kind: .staticGetter,
      );
      final set = FunctionTarget(uri, 'value', .voidType, [
        .integer,
      ], kind: .staticSetter);
      expect(get.parameterTypes, isEmpty);
      expect(set.parameterTypes, [ValueType.integer]);
      expect(get.kind.hasReceiver, isFalse);
      expect(set.kind.isVirtual, isFalse);
      final getBody = Block()..finish(const Return(Constant.integer(1)));
      final setBody = Block(set.parameterTypes)..finish(const Return());
      expect(
        () => IrProgram([], [
          IrFunction(get, [getBody]),
          IrFunction(set, [setBody]),
        ]),
        returnsNormally,
      );
      expect(
        () => FunctionTarget(uri, 'value', .integer, [
          .integer,
        ], kind: .staticGetter),
        throwsArgumentError,
      );
      expect(
        () => FunctionTarget(uri, 'value', .integer, [
          .integer,
        ], kind: .staticSetter),
        throwsArgumentError,
      );
      expect(() => DirectCall(set, []), throwsArgumentError);
    },
  );
}
