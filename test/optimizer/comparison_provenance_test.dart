import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  for (final widenAddress in [false, true]) {
    for (final comparison in ['equals', 'identical', 'integer', 'numeric']) {
      test('$comparison result carries no input address ($widenAddress)', () {
        final fixture = _fixture(comparison, widenAddress: widenAddress);
        final facts = ProgramFlow(fixture.program, [
          (target: fixture.root, arguments: [FlowValue.unknown(.integer)]),
        ]).facts;
        expect(facts.valueOf(fixture.result).references.isBottom, isTrue);
        expect(
          (facts.returnedBy(fixture.root).constant as ScalarConstant).value,
          7,
        );
      });
    }
    test('address arithmetic retains raw memory access ($widenAddress)', () {
      final fixture = _fixture('address', widenAddress: widenAddress);
      final facts = ProgramFlow(fixture.program, [
        (target: fixture.root, arguments: [FlowValue.unknown(.integer)]),
      ]).facts;
      expect(facts.valueOf(fixture.result).references.isBottom, isFalse);
      expect(facts.returnedBy(fixture.root).constant, isNull);
      expect(facts.returnedBy(fixture.root).integers!.contains(7), isTrue);
    });
  }
}

({IrProgram program, FunctionTarget root, Value result}) _fixture(
  String comparison, {
  required bool widenAddress,
}) {
  final box = ClassType(null, 'Private');
  final field = InstanceField(box, 'value', .integer);
  final root = FunctionTarget(null, 'root', .integer, [.integer]);
  final entry = Block(root.parameterTypes);
  final object = entry.emit(NewPayload(box, const Constant.integer(0)));
  entry.emit(StoreField(field, object, const Constant.integer(7)));
  Value address = entry.emit(ReferenceAddress(object));
  if (widenAddress) {
    address = entry.emit(IntBinary(.bitAnd, address, entry.parameters.single));
  }
  final other = entry.parameters.single;
  final result = entry.emit(switch (comparison) {
    'equals' => Equals(address, other),
    'identical' => Identical(address, other),
    'integer' => IntBinary(.lessThan, address, other),
    'numeric' => NumericBinary(.lessThan, address, other),
    _ => IntBinary(.add, address, other),
  });
  final sink = FunctionTarget(null, 'sink', .voidType, [result.type]);
  entry.emit(DirectCall(sink, [result]));
  entry.finish(Return(entry.emit(LoadField(field, object))));
  return (
    program: IrProgram(
      [
        IrClass(box, [field]),
      ],
      [
        IrFunction(root, [entry]),
      ],
      externals: [
        IrExternal(
          sink,
          effects: {Effect.writesStorage},
          capturesArguments: false,
          terminates: true,
        ),
      ],
    ),
    root: root,
    result: result,
  );
}
