import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  const dynamicType = ValueType.dynamicType;

  test('dynamic is a distinct nullable top type, not compiler storage', () {
    expect(dynamicType, const DynamicType());
    expect(dynamicType.hashCode, const DynamicType().hashCode);
    expect(dynamicType.dartName, 'dynamic');
    expect(dynamicType, isNot(ValueType.object.nullable));
    expect(dynamicType.nullable, same(dynamicType));
    expect(dynamicType.nonNullable, same(dynamicType));
    expect(dynamicType.mayBeNull, isTrue);
    for (final type in [
      ValueType.integer,
      ValueType.nullType,
      ValueType.never,
      ValueType.object.nullable,
      RecordType([ValueType.integer]),
      FunctionType(ValueType.integer, []),
    ]) {
      expect(dynamicType.accepts(type), isTrue, reason: type.dartName);
    }
    expect(dynamicType.accepts(CellType(ValueType.integer)), isFalse);
    expect(ValueType.object.nullable.accepts(dynamicType), isTrue);
    expect(ValueType.object.accepts(dynamicType), isFalse);
    expect(ValueType.integer.accepts(dynamicType), isFalse);
    expect(ValueType.integer.nullable.accepts(dynamicType), isFalse);
  });

  test('dynamic generic arguments keep identity and top-type subtyping', () {
    final dynamicList = CoreTypes.listOf(dynamicType);
    final objectList = CoreTypes.listOf(ValueType.object.nullable);
    final intList = CoreTypes.listOf(ValueType.integer);
    expect(dynamicList, isNot(objectList));
    expect(dynamicList.dartName, 'List<dynamic>');
    expect(dynamicList.accepts(objectList), isTrue);
    expect(objectList.accepts(dynamicList), isTrue);
    expect(dynamicList.accepts(intList), isTrue);
    expect(intList.accepts(dynamicList), isFalse);
    expect(dynamicList.validateTypeArguments, returnsNormally);
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    expect(t.substitute({t: dynamicType}), dynamicType);
    expect(
      FunctionType(
        t,
        [t],
        typeParameters: [t],
      ).instantiate([dynamicType]).result,
      dynamicType,
    );
  });

  test('generic bound equivalence is broader than function type identity', () {
    FunctionType identity(ValueType bound) {
      final t = TypeParameterType('T')..initializeBound(bound);
      return FunctionType(t, [t], typeParameters: [t]);
    }

    final nullableBound = identity(ValueType.object.nullable);
    final dynamicBound = identity(dynamicType);
    expect(nullableBound, isNot(dynamicBound));
    expect(nullableBound.accepts(dynamicBound), isTrue);
    expect(dynamicBound.accepts(nullableBound), isTrue);
    final nonNullableBound = identity(ValueType.object);
    expect(dynamicBound.accepts(nonNullableBound), isFalse);
    expect(nonNullableBound.accepts(dynamicBound), isFalse);
    expect(identity(dynamicType), dynamicBound);
    expect(identity(dynamicType).hashCode, dynamicBound.hashCode);
  });

  test('dynamic values need checked narrowing and retain null assertions', () {
    final block = Block([dynamicType]);
    final source = block.parameters.single;
    expect(() => TypeView(source, ValueType.integer), throwsArgumentError);
    final cast = TypeCast(source, ValueType.integer);
    expect(cast.type, ValueType.integer);
    expect(cast.mayThrow, isTrue);
    final checked = NullCheck(source);
    expect(checked.type, dynamicType);
    expect(checked.mayThrow, isTrue);
    expect(ValueType.error.accepts(ValueType.stateError), isTrue);
    expect(ValueType.stateError.dartName, 'StateError');
  });
}
