import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/invocations.dart' as source;

void main() {
  late IrProgram program;
  IrFunction entry(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.kind == .function &&
        body.target.library.toString().endsWith(
          '/codegen/fixtures/invocations.dart',
        ),
  );
  setUpAll(() async {
    await prepareRuntime('test/codegen/fixtures/invocations.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  test('normalized generic getter behavior matches Dart', () {
    expect(source.getterCall(), 19);
    expect(IrInterpreter(program, {}).run(entry('getterCall'), []), 19);
  });
  test('getter result is invoked with its actual generic environment', () {
    final body = entry('getterCall');
    final facts = ProgramOptimizer(const [
      ProgramCallSpecialization(),
      ProgramSimplification(),
    ]).run(program, [(target: body.target, arguments: [])]);
    expect(
      facts.returnedBy(body.target).constant?.structuralKey,
      const Constant.integer(19).structuralKey,
    );
    final result = facts.program.implementationOf(body.target) as IrFunction;
    expect(IrInterpreter(facts.program, {}).run(result, []), 19);
  });
}
