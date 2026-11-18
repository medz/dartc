import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

Iterable<Instruction> _operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  for (final fresh in [false, true]) {
    test(
      'method producers retain captures and broaden with fresh owner=$fresh',
      () {
        final fixture = _Fixture();
        var owner = fixture.owner();
        final partial = CallableLowering(owner)
            .run(fixture.solve(fixture.program, true));
        final firstBinding = fixture.binding(partial).entryBinding!;
        final firstEntry = firstBinding.entries[fixture.members.first]!;
        final broader = fixture.solve(partial, null);
        final extraction = fixture.binding(partial);
        expect(broader.hasUnknownCall(extraction), isFalse);
        expect(broader.pendingExecutionCalls[extraction], {
          fixture.members.last,
        });
        expect(broader.sourceTargetsOf(extraction), fixture.members.toSet());
        expect(broader.targetsOf(extraction), {firstEntry});
        if (fresh) owner = fixture.owner();
        final complete = CallableLowering(owner).run(broader);
        final actual = fixture.binding(complete);
        expect(actual.entryBinding!.entries[fixture.members.first], firstEntry);
        expect(
          actual.entryBinding!.entries.keys.toSet(),
          fixture.members.toSet(),
        );
        final solved = fixture.solve(complete, null);
        expect(solved.pendingExecutionCalls, isEmpty);
        expect(
          solved.targetsOf(actual),
          actual.entryBinding!.entries.values.toSet(),
        );
        final runner = fixture.runner(complete, owner);
        for (final choice in [true, false]) {
          expect(
            runner.run(complete.implementationOf(fixture.root) as IrFunction, [
              choice,
            ]),
            choice ? 41 : 42,
          );
          expect(
            runner.run(
              complete.implementationOf(fixture.read) as IrFunction,
              [],
            ),
            choice ? 7 : 9,
          );
        }
        expect(
          CallableLowering(fresh ? fixture.owner() : owner).run(solved),
          same(complete),
        );
      },
    );
  }

  test(
    'fresh producer owner retains exceptional writes and the source handler',
    () {
      final fixture = _Fixture();
      final partial = CallableLowering(fixture.owner())
          .run(fixture.solve(fixture.program, true));
      final entry = fixture
          .binding(partial)
          .entryBinding!
          .entries[fixture.members.first]!;
      final failed = Block(entry.parameterTypes);
      failed.emit(StoreGlobal(fixture.saved, const Constant.integer(73)));
      failed.finish(Throw(const Constant.integer(99)));
      final graph = IrProgram(
        partial.classes,
        [
          for (final body in partial.functions)
            if (body.target != entry) body,
          IrFunction(entry, [failed]),
        ],
        globals: partial.globals,
        executionShapes: partial.executionShapes,
      );
      final owner = fixture.owner();
      final complete = CallableLowering(owner).run(fixture.solve(graph, null));
      expect(
        fixture.binding(complete).entryBinding!.entries[fixture.members.first],
        entry,
      );
      expect(fixture.solve(complete, null).pendingExecutionCalls, isEmpty);
      final runner = fixture.runner(complete, owner);
      expect(
        runner.run(complete.implementationOf(fixture.root) as IrFunction, [
          true,
        ]),
        73,
      );
      expect(
        runner.run(complete.implementationOf(fixture.root) as IrFunction, [
          false,
        ]),
        42,
      );
    },
  );

  test('a persisted producer cannot refer to a missing or external body', () {
    final fixture = _Fixture();
    final partial = CallableLowering(fixture.owner())
        .run(fixture.solve(fixture.program, true));
    final target = fixture
        .binding(partial)
        .entryBinding!
        .entries[fixture.members.first]!;
    // An explicitly external function cannot replace a compiler-owned producer.
    final broken = IrProgram(
      partial.classes,
      partial.functions.where((body) => body.target != target),
      globals: partial.globals,
      executionShapes: partial.executionShapes,
      externals: [IrExternal(target)],
    );
    expect(() => fixture.solve(broken, true), throwsStateError);
    expect(() => fixture.owner().extend(broken), throwsStateError);
  });
}

final class _Fixture() {
  final face = ClassType(null, 'Face', isAbstract: true);
  late final method = FunctionTarget(
    null,
    'value',
    .integer,
    [],
    owner: face,
    kind: .method,
    isAbstract: true,
  );
  late final types = [
    ClassType(null, 'A', interfaces: [face]),
    ClassType(null, 'B', interfaces: [face]),
  ];
  late final fields = [
    for (final type in types)
      InstanceField(type, 'value', .integer, isFinal: true),
  ];
  late final members = [
    for (final type in types)
      FunctionTarget(null, 'value', .integer, [], owner: type, kind: .method),
  ];
  final root = FunctionTarget(null, 'choose', .integer, [.boolean]);
  final read = FunctionTarget(null, 'read', .integer.nullable, []);
  final saved = GlobalVariable(
    Uri.parse('memory:method-producer'),
    'saved',
    .integer.nullable,
  );
  late final program = build();
  CallableImplementations owner() => CallableImplementations(
    types: TypeImplementations(declarations: [face, ...types]),
  );
  BindMethod binding(IrProgram graph) =>
      _operations(graph.implementationOf(root) as IrFunction)
          .whereType<BindMethod>()
          .single;
  ProgramFlowFacts solve(IrProgram graph, bool? choice) => ProgramFlow(graph, [
    (
      target: root,
      arguments: [
        choice == null
            ? FlowValue.unknown(.boolean)
            : FlowValue.constant(Constant.boolean(choice)),
      ],
    ),
  ]).facts;
  IrInterpreter runner(IrProgram graph, CallableImplementations owner) =>
      IrInterpreter(
        graph,
        {},
        typeLayout: ProgramLayout(
          graph.classes,
          typeImplementations: owner.types,
          executionShapes: graph.executionShapes,
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        ),
      );
  IrProgram build() {
    final functions = <IrFunction>[];
    for (final (index, member) in members.indexed) {
      final block = Block(member.parameterTypes);
      block.emit(StoreGlobal(saved, Constant.integer(index == 0 ? 7 : 9)));
      block.finish(
        Return(block.emit(LoadField(fields[index], block.parameters.first))),
      );
      functions.add(IrFunction(member, [block]));
    }
    final begin = Block(root.parameterTypes),
        select = Block([face]),
        bound = Block([method.signature]),
        failed = Block();
    begin.emit(StoreGlobal(saved, const Constant.integer(1)));
    begin.finish(
      Branch(
        begin.parameters.single,
        Jump(select, [
          ObjectConstant(types.first, {
            fields.first: const Constant.integer(41),
          }),
        ]),
        Jump(select, [
          ObjectConstant(types.last, {fields.last: const Constant.integer(42)}),
        ]),
      ),
    );
    final bind = BindMethod(method, select.parameters.single);
    select.finish(
      Invoke(bind, onReturn: Jump(bound, [bind]), onThrow: Jump(failed)),
    );
    bound.finish(Return(bound.emit(FunctionCall(bound.parameters.single, []))));
    failed.finish(
      Return(failed.emit(NullCheck(failed.emit(LoadGlobal(saved))))),
    );
    final reading = Block();
    reading.finish(Return(reading.emit(LoadGlobal(saved))));
    functions.addAll([
      IrFunction(root, [begin, select, bound, failed]),
      IrFunction(read, [reading]),
    ]);
    return IrProgram(
      [
        IrClass(face, [], members: [method]),
        for (final (index, type) in types.indexed)
          IrClass(type, [fields[index]], members: [members[index]]),
      ],
      functions,
      globals: [saved],
    );
  }
}
