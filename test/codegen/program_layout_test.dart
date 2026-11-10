import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  test('Type constants preserve canonical identity without merging distinct top types', () {
    final data = ConstantData(ProgramLayout([]), 0);
    final types = <ValueType>[
      .integer,
      .dynamicType,
      .voidType,
      .object.nullable,
      .never,
      .nullType,
    ];
    final symbols = types
        .map((type) => data.addressOf(TypeConstant(type)))
        .toList();
    expect(symbols.toSet().length, types.length);
    for (final (i, type) in types.indexed) {
      expect(data.addressOf(TypeConstant(type)), symbols[i]);
    }
  });

  test(
    'type test words retain declaration identity and freeze before emission',
    () {
      final uri = Uri.parse('memory:type-bits');
      final types = [for (var i = 0; i < 66; i++) ClassType(uri, 'SameName')];
      final actual = ClassType(
        uri,
        'Actual',
        interfaces: [types[1], types[63], types[65]],
      );
      final layouts = ProgramLayout([]);
      for (final (i, type) in types.indexed) {
        expect(layouts.typeTest(type), i);
      }
      expect(layouts.typeTestBits(actual), [2 | (1 << 63), 2]);
      expect(layouts.typeTest(types[63]), 63);
      expect(() => layouts.typeTest(.integer), throwsStateError);
    },
  );

  test('Type constants normalize bound variables before nullable unions', () {
    final t = TypeParameterType('T')..initializeBound(ValueType.never);
    final u = TypeParameterType('U')..initializeBound(ValueType.never);
    final data = ConstantData(ProgramLayout([]), 0);
    final a = FunctionType(t.nullable, [t], typeParameters: [t]);
    final b = FunctionType(.nullType, [.never], typeParameters: [u]);
    expect(data.addressOf(TypeConstant(a)), data.addressOf(TypeConstant(b)));
  });

  test(
    'constant objects canonicalize normalized type arguments and Type fields',
    () {
      final t = TypeParameterType('T')..initializeBound(ValueType.never);
      final u = TypeParameterType('U')..initializeBound(ValueType.never);
      final a = FunctionType(t, [t], typeParameters: [t]);
      final b = FunctionType(.never, [.never], typeParameters: [u]);
      final p = TypeParameterType('P')
        ..initializeBound(ValueType.object.nullable);
      final box = ClassType(
        Uri.parse('memory:constant-types'),
        'Box',
        typeParameters: [p],
      );
      final field = InstanceField(box, 'type', .typeType, isFinal: true);
      final data = ConstantData(
        ProgramLayout([
          IrClass(box, [field]),
        ]),
        0,
      );
      int address(ValueType type) => data.addressOf(
        ObjectConstant(box.instantiate([type]), {field: TypeConstant(type)}),
      );
      expect(address(a), address(b));
      expect(address(a), isNot(address(ValueType.integer)));
    },
  );

  test('only Error subclasses retain a traced first-throw slot', () {
    final uri = Uri.parse('memory:error-layout');
    final base = ClassType(uri, 'Base', superclass: ValueType.error);
    final child = ClassType(uri, 'Child', superclass: base);
    final implementation = ClassType(
      uri,
      'Implementation',
      interfaces: [ValueType.error],
    );
    final number = InstanceField(base, 'number', .integer);
    final reference = InstanceField(
      child,
      'reference',
      ValueType.object.nullable,
    );
    final layouts = ProgramLayout([
      IrClass(ValueType.error, []),
      IrClass(base, [number]),
      IrClass(child, [reference]),
      IrClass(implementation, []),
    ]);
    final storage = layouts.storageOf(child);
    expect(layouts.storageOf(ValueType.error).errorTraceOffset, 16);
    expect(layouts.storageOf(base).errorTraceOffset, 24);
    expect(storage.errorTraceOffset, 32);
    expect(storage.layout.size, 40);
    expect(storage.layout.referenceOffsets, [8, 24, 32]);
    expect(layouts.fieldOffset(number), 16);
    expect(layouts.fieldOffset(reference), 24);
    expect(layouts.storageOf(implementation).errorTraceOffset, isNull);
    expect(layouts.storageOf(implementation).layout.referenceOffsets, [8]);
    expect(
      () => ConstantData(
        layouts,
        0,
      ).addressOf(ObjectConstant(ValueType.error, {})),
      throwsUnsupportedError,
    );
  });
}
