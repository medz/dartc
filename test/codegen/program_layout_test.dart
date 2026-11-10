import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
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
    expect(layouts.storageOf(ValueType.error).errorTraceOffset, 8);
    expect(layouts.storageOf(base).errorTraceOffset, 16);
    expect(storage.errorTraceOffset, 24);
    expect(storage.layout.size, 32);
    expect(storage.layout.referenceOffsets, [16, 24]);
    expect(layouts.fieldOffset(number), 8);
    expect(layouts.fieldOffset(reference), 16);
    expect(layouts.storageOf(implementation).errorTraceOffset, isNull);
    expect(layouts.storageOf(implementation).layout.referenceOffsets, isEmpty);
    expect(
      () => ConstantData(
        layouts,
        0,
      ).addressOf(ObjectConstant(ValueType.error, {})),
      throwsUnsupportedError,
    );
  });
}
