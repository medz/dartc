import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

Iterable<Instruction> _operations(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = (await prepareRuntime(
      'test/codegen/fixtures/scalar_semantic_views.dart',
    )).program;
  });
  for (final name in ['f', 'g']) {
    test(
      'default $name preserves a scalar language view without allocation',
      () {
        final source = program.functions.singleWhere(
          (f) =>
              f.target.name == name &&
              f.target.library.toString().endsWith(
                '/codegen/fixtures/scalar_semantic_views.dart',
              ),
        );
        final prepared = Compiler(const Target(.linux, .arm64))
            .prepare(program, roots: [source.target], runtime: heapRuntime);
        final body =
            prepared.program.implementationOf(source.target) as IrFunction;
        expect(
          _operations(body)
              .where((op) => op.effects.contains(Effect.allocates)),
          isEmpty,
        );
        final runner = IrInterpreter(prepared.program, {});
        for (final n in [-7, 0, 42]) {
          final actual = runner.run(body, [n]);
          if (name == 'f') {
            expect(actual, isTrue);
          } else {
            final oracle = IrFunction(
              FunctionTarget(null, 'intType', .typeType, []),
              [Block()..finish(Return(TypeConstant(.integer)))],
            );
            expect(actual, runner.run(oracle, []));
          }
        }
      },
    );
  }
}
