import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final freshOwner in [false, true]) {
    test(
      'broader callable inputs realize their source with freshOwner=$freshOwner',
      () {
        final fixture = _Fixture();
        final owner = CallableImplementations();
        final partial = CallableLowering(owner)
            .run(fixture.facts(fixture.program, onlyFirst: true));
        final firstCall = _call(partial, fixture.root);
        final originalEntry = firstCall.entryBinding!.entries[fixture.first]!;
        final broader = fixture.facts(partial);
        final call = _call(partial, fixture.root);
        expect(broader.hasUnknownCall(call), isFalse);
        expect(broader.pendingExecutionCalls[call], {fixture.second});
        expect(broader.targetsOf(call), {originalEntry, fixture.second});
        expect(
          () => ProgramPreparation(
            const Target(.linux, .arm64),
            partial,
            boundaries: NativeBoundaries(partial, roots: [fixture.root]),
          ).prepare(broader),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Execution entries remain unimplemented'),
            ),
          ),
        );
        final lowered = CallableLowering(
          freshOwner ? CallableImplementations() : owner,
        ).run(broader);
        final closed = fixture.facts(lowered);
        final actual = _call(lowered, fixture.root);
        expect(actual.entryBinding!.entries.keys.toSet(), {
          fixture.first,
          fixture.second,
        });
        expect(actual.entryBinding!.entries[fixture.first], originalEntry);
        expect(closed.pendingExecutionCalls, isEmpty);
        expect(closed.hasUnknownCall(actual), isFalse);
        expect(
          closed.targetsOf(actual),
          actual.entryBinding!.entries.values.toSet(),
        );
        final runner = IrInterpreter(lowered, {});
        final root = lowered.implementationOf(fixture.root) as IrFunction;
        expect(runner.run(root, [true]), 42);
        expect(runner.run(root, [false]), 43);
        expect(
          CallableLowering(freshOwner ? CallableImplementations() : owner)
              .run(closed),
          same(lowered),
        );
      },
    );
  }

  test('default compiler closes a retained source branch with a new callable target', () {
    final fixture = _Fixture();
    final partial = CallableLowering(CallableImplementations())
        .run(fixture.facts(fixture.program, onlyFirst: true));
    final prepared = Compiler(const Target(.linux, .arm64))
        .prepare(partial, roots: [fixture.root]);
    final runner = IrInterpreter(prepared.program, {});
    final root = prepared.program.implementationOf(fixture.root) as IrFunction;
    expect(runner.run(root, [true]), 42);
    expect(runner.run(root, [false]), 43);
  });

  test(
    'pending known execution keeps real prior writes and the caught exception',
    () {
      final saved = GlobalVariable(
        Uri.parse('memory:callable-demand'),
        'saved',
        .integer.nullable,
      );
      final first = FunctionTarget(null, 'normal', .integer, []);
      final second = FunctionTarget(null, 'throwsAfterWrite', .integer, []);
      final firstBody = Block()..finish(const Return(Constant.integer(42)));
      final secondBody = Block();
      secondBody.emit(StoreGlobal(saved, const Constant.integer(9)));
      secondBody.finish(Throw(const Constant.integer(73)));
      final root = FunctionTarget(null, 'choose', .integer.nullable, [
        .boolean,
      ]);
      final begin = Block(root.parameterTypes),
          yes = Block(),
          no = Block(),
          join = Block([first.signature]),
          returned = Block([.integer]),
          caught = Block();
      begin.emit(StoreGlobal(saved, const Constant.integer(1)));
      begin.finish(Branch(begin.parameters.single, Jump(yes), Jump(no)));
      yes.finish(Jump(join, [FunctionConstant(first)]));
      no.finish(Jump(join, [FunctionConstant(second)]));
      final call = FunctionCall(join.parameters.single, []);
      join.finish(
        Invoke(call, onReturn: Jump(returned, [call]), onThrow: Jump(caught)),
      );
      returned.finish(Return(returned.parameters.single));
      caught.finish(Return(caught.emit(LoadGlobal(saved))));
      final program = IrProgram(
        [],
        [
          IrFunction(first, [firstBody]),
          IrFunction(second, [secondBody]),
          IrFunction(root, [begin, yes, no, join, returned, caught]),
        ],
        globals: [saved],
      );
      ProgramFlowFacts facts(IrProgram graph, bool? choose) =>
          ProgramFlow(graph, [
            (
              target: root,
              arguments: [
                choose == null
                    ? FlowValue.unknown(ValueType.boolean)
                    : FlowValue.constant(Constant.boolean(choose)),
              ],
            ),
          ]).facts;
      final owner = CallableImplementations();
      final partial = CallableLowering(owner).run(facts(program, true));
      final broader = facts(partial, null);
      expect(broader.pendingExecutionCalls.values.expand((v) => v).toSet(), {
        second,
      });
      final completed = CallableLowering(owner).run(broader);
      expect(facts(completed, null).pendingExecutionCalls, isEmpty);
      for (final graph in [program, partial, completed]) {
        if (identical(graph, partial))
          continue; // This graph deliberately lacks the second machine entry.
        final runner = IrInterpreter(graph, {});
        final body = graph.implementationOf(root) as IrFunction;
        expect(runner.run(body, [true]), 42);
        expect(runner.run(body, [false]), 9);
      }
      final caughtResult =
          facts(partial, false).returnedBy(root).constant as ScalarConstant;
      expect(caughtResult.value, 9);
    },
  );
}

FunctionCall _call(IrProgram program, FunctionTarget target) =>
    (program.implementationOf(target) as IrFunction).blocks
        .expand(
          (block) => [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        )
        .whereType<FunctionCall>()
        .single;

final class _Fixture() {
  final first = FunctionTarget(null, 'first', .integer, []);
  final second = FunctionTarget(null, 'second', .integer, []);
  final root = FunctionTarget(null, 'choose', .integer, [.boolean]);
  late final IrProgram program = _build();
  IrProgram _build() {
    final begin = Block(root.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block([first.signature]);
    begin.finish(Branch(begin.parameters.single, Jump(yes), Jump(no)));
    yes.finish(Jump(join, [FunctionConstant(first)]));
    no.finish(Jump(join, [FunctionConstant(second)]));
    join.finish(Return(join.emit(FunctionCall(join.parameters.single, []))));
    return IrProgram([], [
      IrFunction(first, [Block()..finish(const Return(Constant.integer(42)))]),
      IrFunction(second, [Block()..finish(const Return(Constant.integer(43)))]),
      IrFunction(root, [begin, yes, no, join]),
    ]);
  }

  ProgramFlowFacts facts(IrProgram graph, {bool onlyFirst = false}) =>
      ProgramFlow(graph, [
        (
          target: root,
          arguments: [
            onlyFirst
                ? FlowValue.constant(const Constant.boolean(true))
                : FlowValue.unknown(ValueType.boolean),
          ],
        ),
      ]).facts;
}
