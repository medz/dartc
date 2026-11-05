import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  TypeParameterType parameter(String name) =>
      TypeParameterType(name)..initializeBound(ValueType.object.nullable);
  test('type constants require closed source types including nested slots', () {
    final t = parameter('T');
    for (final type in <ValueType>[
      t,
      CoreTypes.listOf(t),
      CellType(ValueType.integer),
    ]) {
      expect(() => TypeConstant(type), throwsArgumentError);
    }
    final generic = FunctionType(t, [t], typeParameters: [t]);
    expect(TypeConstant(generic).type, ValueType.typeType);
    expect(
      TypeConstant(ValueType.voidType).representedType,
      ValueType.voidType,
    );
    expect(
      constantKey(TypeConstant(ValueType.integer)),
      constantKey(TypeConstant(ValueType.integer)),
    );
    expect(
      constantKey(TypeConstant(ValueType.dynamicType)),
      isNot(constantKey(TypeConstant(ValueType.object.nullable))),
    );
  });
  test('reification is pure and verifier checks lexical template scope', () {
    final t = parameter('T');
    final op = ReifyType(CoreTypes.listOf(t));
    expect(op.inputs, isEmpty);
    expect(op.mayThrow, isFalse);
    final block = Block();
    block.emit(op);
    block.finish(Return(op));
    expect(
      () => IrFunction(
        FunctionTarget(Uri.parse('memory:type'), 'bad', ValueType.typeType, []),
        [block],
      ),
      throwsStateError,
    );
    final good = Block();
    final result = good.emit(ReifyType(CoreTypes.listOf(t)));
    good.finish(Return(result));
    expect(
      () => IrFunction(
        FunctionTarget(
          Uri.parse('memory:type'),
          'good',
          ValueType.typeType,
          [],
          typeParameters: [t],
        ),
        [good],
      ),
      returnsNormally,
    );
    expect(() => ReifyType(CellType(ValueType.integer)), throwsArgumentError);
  });
}
