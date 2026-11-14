import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';
import 'fixtures/reference_payload.dart' as source;

void main() {
  late IrProgram program;
  late ProgramLayout layout;
  IrFunction body(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.library.toString().endsWith(
          '/optimizer/fixtures/reference_payload.dart',
        ),
  );
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/reference_payload.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
    layout = ProgramLayout(
      program.classes,
      nativeLayout: NativeLayout(Target.host()),
      functions: program.functions,
      typeRuntime: heapRuntime.types,
    );
  });

  test('ordinary SDK lists carry overwritten function values through their reference payload', () {
    final function = body('replacedFunction');
    final facts = ProgramFlow(program, [
      (
        target: function.target,
        arguments: [FlowValue.constant(const Constant.integer(41))],
      ),
    ], memoryLayout: layout).facts;
    expect(
      facts.returnedBy(function.target).constant?.structuralKey,
      Constant.integer(source.replacedFunction(41)).structuralKey,
    );
    expect(facts.definitions, isNot(contains(body('unused').target)));
  });

  for (final (name, value) in [
    ('carriedInteger', const Constant.integer(37)),
    ('carriedObject', const Constant.string('kept')),
  ]) {
    test('generic SDK list payload retains $name', () {
      final function = body(name);
      final facts = ProgramFlow(program, [
        (target: function.target, arguments: [FlowValue.constant(value)]),
      ], memoryLayout: layout).facts;
      expect(
        facts.returnedBy(function.target).constant?.structuralKey,
        value.structuralKey,
      );
    });
  }
}
