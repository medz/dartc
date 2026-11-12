import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'payload allocation retains declaration identity and traced storage',
    () {
      final type = ClassType(null, 'References');
      final declaration = IrClass(type, [], referencePayload: true);
      final entry = Block([.integer]);
      final value = entry.emit(NewPayload(type, entry.parameters.single));
      entry.finish(Return(value));
      final function = IrFunction(
        FunctionTarget(null, 'allocate', type, [.integer]),
        [entry],
      );
      IrProgram([declaration], [function]);
      expect(function.instantiatedClasses, contains(same(type)));
      expect(value.effects, {Effect.allocates});
      expect(
        () => IrClass(type, [
          InstanceField(type, 'value', .integer),
        ], referencePayload: true),
        throwsArgumentError,
      );
      expect(
        () => NewPayload(type, const Constant.boolean(false)),
        throwsArgumentError,
      );
      expect(
        () => NewPayload(
          ClassType(null, 'Abstract', isAbstract: true),
          const Constant.integer(8),
        ),
        throwsArgumentError,
      );
      expect(
        () => IrClass(
          ClassType(null, 'Derived', superclass: type),
          [],
          referencePayload: true,
        ),
        throwsArgumentError,
      );
    },
  );

  test('constant Lists require distinct storage slots and a typed spread', () {
    final element = TypeParameterType('E')
      ..initializeBound(ValueType.object.nullable)
      ..initializeDefaultType(ValueType.dynamicType);
    final type = ClassType.declare(null, 'Items', typeParameters: [element])
      ..initializeHierarchy(interfaces: [CoreTypes.listOf(element)]);
    final length = InstanceField(type, 'length', .integer);
    final data = InstanceField(type, 'data', ClassType(null, 'References'));
    final mode = InstanceField(type, 'mode', .integer);
    final parameter = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable)
      ..initializeDefaultType(ValueType.dynamicType);
    final spread = FunctionTarget(
      null,
      'spread',
      .voidType,
      [
        CoreTypes.listOf(parameter),
        CoreTypes.iterableOf(ValueType.object.nullable),
      ],
      typeParameters: [parameter],
    );
    IrClass(
      type,
      [length, data, mode],
      listStorage: (
        length: length,
        data: data,
        mutability: mode,
        spread: spread,
      ),
    );
    expect(
      () => IrClass(
        type,
        [length, data, mode],
        listStorage: (
          length: length,
          data: data,
          mutability: length,
          spread: spread,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => IrClass(
        type,
        [length, data, mode],
        listStorage: (
          length: length,
          data: data,
          mutability: mode,
          spread: FunctionTarget(null, 'untyped', .voidType, []),
        ),
      ),
      throwsArgumentError,
    );
  });
}
