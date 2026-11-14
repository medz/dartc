import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/call_specialization.dart' as source;

void main() {
  late IrProgram program;
  final optimizer = ProgramOptimizer(const [
    ProgramSimplification(),
    ProgramCallSpecialization(),
    ProgramStoragePromotion(),
    ProgramStorageElimination(),
  ]);
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/call_specialization.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  test('unknown values cross generic calls and fields without containers', () {
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'forward',
    );
    final facts = optimizer.run(program, [
      (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
    ]);
    final body = facts.program.implementationOf(entry.target) as IrFunction;
    final interpreter = IrInterpreter(facts.program, {});
    for (final value in [-37, 0, 9, 0x7fffffffffffffff]) {
      expect(interpreter.run(body, [value]), source.forward(value));
    }
    expect(
      body.blocks
          .expand((block) => block.instructions)
          .where(
            (operation) =>
                operation is Construct ||
                operation is LoadField ||
                operation is StoreField ||
                operation is InstanceCall ||
                operation is DirectCall,
          ),
      isEmpty,
    );
  });

  test('a known receiver binds a direct call with unknown arguments', () {
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'dispatch',
    );
    final result = const ProgramCallSpecialization().run(
      ProgramFlow(program, [
        (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
      ]).facts,
    );
    final body = result.implementationOf(entry.target) as IrFunction;
    expect(
      body.callees.where((target) => target.kind == .method).single.name,
      'add',
    );
    expect(body.virtualMembers, isEmpty);
    final interpreter = IrInterpreter(result, {});
    for (final value in [-9, 0, 12]) {
      expect(interpreter.run(body, [value]), source.dispatch(value));
    }
  });

  for (final entry in <String, int Function()>{
    'rejectedWrite': source.rejectedWrite,
    'defaultArgument': source.defaultArgument,
  }.entries) {
    test('specialization preserves ${entry.key}', () {
      final function = program.functions.singleWhere(
        (f) => f.target.name == entry.key,
      );
      final facts = optimizer.run(program, [
        (target: function.target, arguments: <FlowValue>[]),
      ]);
      final body =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(IrInterpreter(facts.program, {}).run(body, []), entry.value());
    });
  }
}
