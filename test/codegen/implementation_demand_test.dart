import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'default compilation does not normalize an uncalled physical return',
    () {
      final root = FunctionTarget(null, 'root', .integer, []);
      final unused = FunctionTarget(null, 'unused', .integer.nullable, [
        .integer,
      ]);
      final external = FunctionTarget(null, 'external', .integer, []);
      final start = Block(unused.parameterTypes),
          success = Block(),
          failure = Block();
      final call = DirectCall(external, []);
      start.finish(
        Invoke(call, onReturn: Jump(success), onThrow: Jump(failure)),
      );
      success.finish(Return(start.parameters.single));
      failure.finish(const Return(Constant.nullValue()));
      final program = IrProgram(
        [],
        [
          IrFunction(root, [
            Block()..finish(const Return(Constant.integer(42))),
          ]),
          IrFunction(unused, [start, success, failure]),
        ],
        externals: [IrExternal(external)],
      );
      final prepared = Compiler(const Target(.linux, .arm64))
          .prepare(program, roots: [root]);
      expect(prepared.definitions, {root});
      expect(
        IrInterpreter(
          prepared.program,
          {},
        ).run(prepared.program.implementationOf(root) as IrFunction, []),
        42,
      );
    },
  );

  test('default literal dead type check does not demand runtime support', () {
    final root = FunctionTarget(null, 'root', .boolean, [.object]);
    final entry = Block(root.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(const Constant.boolean(true), Jump(yes), Jump(no)));
    yes.finish(const Return(Constant.boolean(true)));
    no.finish(
      Return(no.emit(TypeTest(entry.parameters.single, ValueType.integer))),
    );
    final prepared = Compiler(const Target(.linux, .arm64)).prepare(
      IrProgram([], [
        IrFunction(root, [entry, yes, no]),
      ]),
      roots: [root],
    );
    expect(prepared.definitions, {root});
    expect(
      IrInterpreter(
        prepared.program,
        {},
      ).run(prepared.program.implementationOf(root) as IrFunction, ['text']),
      isTrue,
    );
  });

  test(
    'type implementation demand can grow on the retained original branch',
    () {
      final root = FunctionTarget(null, 'root', .boolean, [.boolean, .object]);
      final entry = Block(root.parameterTypes), yes = Block(), no = Block();
      entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
      final query = yes.emit(
        TypeTest(entry.parameters.last, ValueType.integer),
      );
      yes.finish(Return(query));
      no.finish(const Return(Constant.boolean(false)));
      final program = IrProgram([], [
        IrFunction(root, [entry, yes, no]),
      ]);
      ProgramFlowFacts facts(IrProgram graph, bool condition) =>
          ProgramFlow(graph, [
            (
              target: root,
              arguments: [
                FlowValue.constant(Constant.boolean(condition)),
                FlowValue.unknown(ValueType.object),
              ],
            ),
          ]).facts;
      final transform = TypeLowering(
        TypeImplementations(),
        failure: null,
      ).bind();
      final untouched = transform(facts(program, false));
      expect(untouched, same(program));
      expect(facts(untouched, true).reachesOperation(query), isTrue);
      expect(() => transform(facts(untouched, true)), throwsUnsupportedError);
    },
  );

  test('global implementation demand retains a later reachable binding', () {
    final global = GlobalVariable(
      Uri.parse('memory:demand'),
      'value',
      .integer,
      isLate: true,
    );
    final root = FunctionTarget(null, 'root', .integer, [.boolean]);
    final entry = Block(root.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    final read = yes.emit(LoadGlobal(global));
    yes.finish(Return(read));
    no.finish(const Return(Constant.integer(0)));
    final program = IrProgram(
      [],
      [
        IrFunction(root, [entry, yes, no]),
      ],
      globals: [global],
    );
    ProgramFlowFacts facts(IrProgram graph, bool condition) =>
        ProgramFlow(graph, [
          (
            target: root,
            arguments: [FlowValue.constant(Constant.boolean(condition))],
          ),
        ]).facts;
    final transform = GlobalLowering().bind();
    final untouched = transform(facts(program, false));
    expect(untouched, same(program));
    expect(untouched.globals, [global]);
    expect(facts(untouched, true).reachesOperation(read), isTrue);
    expect(() => transform(facts(untouched, true)), throwsUnsupportedError);
  });
}
