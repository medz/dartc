import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/frontend/lowering/fixtures/execution_shapes.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  Iterable<Instruction> operations(IrFunction function) sync* {
    for (final block in function.blocks) {
      yield* block.instructions;
      if (block.end case Invoke(:final operation)) yield operation;
    }
  }

  for (final name in ['storeScalar', 'returnScalar', 'nullableJoin']) {
    test('$name retains the lexical handler at scalar materialization', () {
      final function = program.functions.singleWhere(
        (f) => f.target.name == name,
      );
      final allocation = operations(function)
          .whereType<MaterializeValue>()
          .single;
      final block = function.blocks.singleWhere(
        (block) =>
            block.end is Invoke &&
            identical((block.end as Invoke).operation, allocation),
      );
      final invoke = block.end as Invoke;
      expect(invoke.onThrow.target, isNot(same(invoke.onReturn!.target)));
      expect(
        function.execution!.values[invoke.onReturn!.target.parameters.single],
        ExecutionShape.reference,
      );
      expect(invoke.operation.type, ValueType.integer);
    });
  }

  for (final name in ['scalarLocalTest', 'scalarViewRuntimeType']) {
    test('$name does not force scalar SSA through declared Object storage', () {
      final function = program.functions.singleWhere((f) => f.target.name == name);
      expect(operations(function).whereType<MaterializeValue>(), isEmpty);
    });
  }

  test('a discarded semantic view does not select heap storage', () {
    final function = program.functions.singleWhere(
      (f) => f.target.name == 'discardedView',
    );
    expect(operations(function).whereType<MaterializeValue>(), isEmpty);
    expect(operations(function).whereType<TypeView>(), hasLength(1));
  });
}
