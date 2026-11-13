import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'record carriers retain methods for constructed and constant records',
    () {
      final carrier = ClassType(
        null,
        'RecordValue',
        interfaces: [ValueType.record],
      );
      final getter = FunctionTarget(
        null,
        'hashCode',
        .integer,
        [],
        owner: carrier,
        kind: .getter,
      );
      final declaration = IrClass(
        carrier,
        [],
        members: [getter],
        referencePayload: true,
        recordStorage: true,
      );
      final hash = Block(getter.parameterTypes)
        ..finish(const Return(Constant.integer(1)));
      final shape = RecordType([.integer]);
      for (final constant in [false, true]) {
        final entry = Block();
        final fields = [const Constant.integer(42)];
        final record = constant
            ? RecordConstant(shape, fields)
            : entry.emit(MakeRecord(shape, fields));
        entry.finish(Return(entry.emit(ObjectHashCode(record))));
        final body = IrFunction(FunctionTarget(null, 'main', .integer, []), [
          entry,
        ]);
        final program = IrProgram(
          [declaration],
          [
            body,
            IrFunction(getter, [hash]),
          ],
        );
        expect(body.recordTypes, {shape});
        expect(shape.mayHaveInstance(carrier), isTrue);
        expect(program.reachableFrom([body.target]), contains(getter));
      }
      expect(
        () => IrClass(carrier, [], recordStorage: true),
        throwsArgumentError,
      );
      expect(
        () => IrClass(
          ClassType(null, 'Other'),
          [],
          referencePayload: true,
          recordStorage: true,
        ),
        throwsArgumentError,
      );
    },
  );

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
      expect(value.effects, {Effect.allocates, Effect.mayThrow});
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
      [length, data],
      listStorage: (length: length, data: data, spread: spread),
    );
    expect(
      () => IrClass(
        type,
        [length, data],
        listStorage: (length: length, data: length, spread: spread),
      ),
      throwsArgumentError,
    );
    expect(
      () => IrClass(
        type,
        [length, data],
        listStorage: (
          length: length,
          data: data,
          spread: FunctionTarget(null, 'untyped', .voidType, []),
        ),
      ),
      throwsArgumentError,
    );
  });
}
