import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

Iterable<Instruction> operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  setUpAll(
    () => prepareRuntime('test/compiler/fixtures/generic_member_carriers.dart'),
  );

  void checkRecursiveEntries({required bool replay}) {
    final program = heapRuntime.program;
    final root = program.functions.singleWhere(
      (f) => f.target.name == 'selectWord',
    );
    final types = TypeImplementations(runtime: heapRuntime.types);
    ProgramLayout layout(IrProgram p) => ProgramLayout(
      p.classes,
      functions: p.functions,
      typeImplementations: types,
      nativeLayout: NativeLayout(Target.host()),
      executionShapes: p.executionShapes,
    );
    final pass = MemberEntryLowering(types).bind();
    var graph = pass(
      ProgramFlow(
        program,
        const [],
        openEntries: [root.target],
        memoryLayout: layout(program),
      ).facts,
    );
    if (replay) {
      final recipes = pass.realizations.toList();
      pass.rebase(program);
      graph = program;
      for (final recipe in recipes) {
        graph = recipe.apply(graph);
      }
    }
    final caller = graph.implementationOf(root.target) as IrFunction;
    final call = operations(caller).whereType<InstanceCall>().single;
    final adapter = graph.implementationOf(
      call.entryBinding!.entries.values.single,
    ) as IrFunction;
    expect(adapter.entry.end, isA<Branch>());
    final guard = adapter.entry.end as Branch;
    final scalar = guard.ifTrue.target;
    final shared = guard.ifFalse.target;
    expect(scalar.instructions.whereType<MaterializeValue>(), isEmpty);
    expect(shared.instructions.whereType<MaterializeValue>(), hasLength(2));
    final scalarTarget = scalar.instructions
        .whereType<DirectCall>()
        .single
        .target;
    final entry = graph.executionShapes!.entryOf(scalarTarget);
    expect(entry.parameters, [
      ExecutionShape.reference,
      ...List.filled(3, ExecutionShape.word),
    ]);
    expect(entry.result, ExecutionShape.word);
    final concrete = graph.implementationOf(scalarTarget) as IrFunction;
    expect(
      operations(concrete).whereType<InstanceCall>().single.member,
      call.member,
    );
    final machine = IrInterpreter(graph, {}, typeLayout: layout(graph));
    for (final mode in [0, 1]) {
      expect(machine.run(caller, [mode, 13, -72, 3]), -72);
      expect(machine.run(caller, [mode, -9, 87, 2]), -9);
    }
  }

  test('a source recursive call reaches both physical entries before specialization',
      () => checkRecursiveEntries(replay: false));
  test('canonical replay preserves both physical entries of a recursive method',
      () => checkRecursiveEntries(replay: true));

  test('replay keeps a canonical member with explicit carriers and handler', () {
    final program = heapRuntime.program;
    final root = program.functions.singleWhere((f) => f.target.name == 'selectWord');
    final source = program.functions.singleWhere((f) =>
        f.target.owner?.name == 'Selector' && f.target.name == 'select');
    final types = TypeImplementations(runtime: heapRuntime.types);
    ProgramLayout layout(IrProgram p) => ProgramLayout(p.classes,
        functions: p.functions, typeImplementations: types,
        nativeLayout: NativeLayout(Target.host()), executionShapes: p.executionShapes);
    final pass = MemberEntryLowering(types).bind();
    pass(ProgramFlow(program, const [], openEntries: [root.target],
        memoryLayout: layout(program)).facts);
    final recipes = pass.realizations.toList();

    final entry = Block(source.target.parameterTypes);
    final ready = Block([ValueType.integer]), caught = Block();
    final materialize = MaterializeValue(entry.parameters.last);
    entry.finish(Invoke(materialize, onReturn: Jump(ready, [materialize]),
        onThrow: Jump(caught)));
    final payload = ready.emit(ProjectValue(ready.parameters.single, ExecutionShape.word));
    ready.finish(Jump(source.entry, [...entry.parameters.take(3), payload]));
    caught.finish(Return(entry.parameters[2]));
    final custom = IrFunction(source.target, [entry, ready, caught, ...source.blocks],
        execution: FunctionExecution({materialize: ExecutionShape.reference,
          ready.parameters.single: ExecutionShape.reference, payload: ExecutionShape.word}));
    var graph = IrProgram(program.classes,
        [for (final f in program.functions) identical(f, source) ? custom : f],
        globals: program.globals, externals: program.externals,
        nativeBoundaries: program.nativeBoundaries, executionShapes: program.executionShapes);
    pass.rebase(graph);
    for (final recipe in recipes) {
      graph = recipe.apply(graph);
    }
    final implementations = graph.functions.where((f) => f.target.executionSource == source.target);
    final shared = implementations.single;
    expect(shared.target.typeParameters, isNotEmpty);
    final invoke = shared.entry.end as Invoke;
    expect(shared.originOf(invoke.operation).source, custom.originOf(materialize).source);
    expect(shared.originOf(operations(shared).whereType<ProjectValue>().single).source,
        custom.originOf(payload).source);
    expect(invoke.onThrow.target.end, isA<Return>());
    expect((invoke.onThrow.target.end as Return).value, shared.entry.parameters[2]);
    final shapes = graph.executionShapes!;
    expect(shapes.shapeOf(shared, invoke.operation), ExecutionShape.reference);
    expect(shapes.shapeOf(shared, invoke.onReturn!.target.parameters.single),
        ExecutionShape.reference);
    expect(ProgramFlow(graph, const [], openEntries: [root.target],
        memoryLayout: layout(graph)).facts.roots, {root.target});
  });

  for (final direct in [false, true]) {
    test(
      'generic member executes checked ordinary body with direct=$direct',
      () {
        final t = TypeParameterType('T')..initializeBound(.object.nullable);
        final declaration = ClassType(
          null,
          'GenericReceiver',
          typeParameters: [t],
        );
        final type = declaration.instantiate([ValueType.integer]);
        final member = FunctionTarget(
          null,
          'read',
          t,
          [t],
          owner: declaration,
          kind: .method,
        );
        // The body must consume the real value, rather than only return a constant.
        final methodBody = Block(member.parameterTypes);
        methodBody.finish(Return(methodBody.parameters.last));
        final root = FunctionTarget(null, 'genericInvoke', .integer, [
          type,
          .integer,
        ]);
        final entry = Block(root.parameterTypes);
        final call = entry.emit(
          direct
              ? DirectCall(member, entry.parameters, ownerType: type)
              : InstanceCall(member, entry.parameters.first, [
                  entry.parameters.last,
                ]),
        );
        entry.finish(Return(call));
        final runtime = heapRuntime;
        final program = IrProgram(
          [
            ...runtime.program.classes,
            IrClass(declaration, [], members: [member]),
          ],
          [
            ...runtime.program.functions,
            IrFunction(member, [methodBody]),
            IrFunction(root, [entry]),
          ],
          globals: runtime.program.globals,
          externals: runtime.program.externals,
        );
        final owner = TypeImplementations(runtime: runtime.types);
        final lower = MemberEntryLowering(owner).bind();
        ProgramLayout layout(IrProgram p) => ProgramLayout(
          p.classes,
          functions: p.functions,
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
          typeImplementations: owner,
          executionShapes: p.executionShapes,
        );
        final inputs = [
          (
            target: root,
            arguments: [
              FlowValue.constant(ObjectConstant(type, {})),
              FlowValue.unknown(ValueType.integer),
            ],
          ),
        ];
        final before = ProgramFlow(
          program,
          inputs,
          memoryLayout: layout(program),
        ).facts;
        final bound = lower(before);
        final variants = bound.functions.where(
          (f) => f.target.executionSource == member,
        );
        final ordinary = variants.singleWhere(
          (f) => f.target.typeParameters.isNotEmpty,
        );
        final scalar = variants.singleWhere(
          (f) => f.target.typeParameters.isEmpty,
        );
        final physical = bound.executionShapes!.entryOf(scalar.target);
        expect(physical.parameters, [
          ExecutionShape.reference,
          ExecutionShape.word,
        ]);
        expect(physical.result, ExecutionShape.word);
        expect(ordinary.target.kind, FunctionKind.function);
        expect(ordinary.target.owner, isNull);
        expect(ordinary.target.typeParameters, [t]);
        final adapter = bound.functions.singleWhere(
          (f) => f.callees.contains(ordinary.target),
        );
        final guard = adapter.entry.end as Branch;
        expect(guard.condition, isA<Equals>());
        final passed = guard.ifTrue.target;
        expect(passed.instructions.whereType<MaterializeValue>(), isEmpty);
        expect(
          passed.instructions.whereType<DirectCall>().single.target,
          scalar.target,
        );
        expect(
          guard.ifFalse.target.instructions.whereType<MaterializeValue>(),
          hasLength(1),
        );
        final invocation = operations(adapter)
            .whereType<DirectCall>()
            .singleWhere((op) => op.target == ordinary.target);
        expect(invocation.typeArguments, [t]);
        expect(invocation.ownerType, isNull);
        final facts = ProgramOptimizer([
          MemberEntryLowering(owner),
          CallableLowering(CallableImplementations(types: owner)),
          RepresentationLowering(),
        ]).run(bound, inputs, memoryLayoutFor: layout);
        expect(facts.pendingExecutionCalls, isEmpty);
        expect(facts.definitions, contains(scalar.target));
        expect(facts.definitions, isNot(contains(member)));
        final current = RepresentationLowering().run(facts);
        final model = IrInterpreter(current, {}, typeLayout: layout(current));
        for (final input in [-7, 0, 42]) {
          final invoke = Block();
          invoke.finish(
            Return(
              invoke.emit(
                DirectCall(root, [
                  ObjectConstant(type, {}),
                  Constant.integer(input),
                ]),
              ),
            ),
          );
          expect(
            model.run(
              IrFunction(FunctionTarget(null, 'fixture', .integer, []), [
                invoke,
              ]),
              [],
            ),
            input,
          );
        }
      },
    );
  }
  test(
    'a wider receiver keeps its real generic checks and invocation body',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final holder = ClassType(null, 'Holder', typeParameters: [t]);
      final source = FunctionTarget(
        null,
        'choose',
        .integer,
        [t],
        owner: holder,
        kind: .method,
      );
      final body = Block(source.parameterTypes);
      final word = Block(), other = Block();
      body.finish(
        Branch(
          body.emit(
            Equals(body.emit(ReifyType(t)), TypeConstant(ValueType.integer)),
          ),
          Jump(word),
          Jump(other),
        ),
      );
      word.finish(Return(word.emit(TypeCast(body.parameters.last, .integer))));
      other.finish(const Return(Constant.integer(-1)));
      final widened = holder.instantiate([ValueType.object.nullable]);
      final root = FunctionTarget(null, 'invoke', .integer, [
        widened,
        .integer,
      ]);
      final entry = Block(root.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            InstanceCall(source, entry.parameters.first, [
              entry.parameters.last,
            ]),
          ),
        ),
      );
      final runtime = heapRuntime;
      final program = IrProgram(
        [
          ...runtime.program.classes,
          IrClass(holder, [], members: [source]),
        ],
        [
          ...runtime.program.functions,
          IrFunction(source, [body, word, other]),
          IrFunction(root, [entry]),
        ],
        globals: runtime.program.globals,
        externals: runtime.program.externals,
      );
      final types = TypeImplementations(runtime: runtime.types);
      ProgramLayout layout(IrProgram p) => ProgramLayout(
        p.classes,
        functions: p.functions,
        typeImplementations: types,
        nativeLayout: NativeLayout(const Target(.macos, .arm64)),
        executionShapes: p.executionShapes,
      );
      final graph = MemberEntryLowering(types).run(
        ProgramFlow(
          program,
          const [],
          openEntries: [root],
          memoryLayout: layout(program),
        ).facts,
      );
      final machine = IrInterpreter(graph, {}, typeLayout: layout(graph));
      int call(ValueType actual) {
        final invoke = Block();
        invoke.finish(
          Return(
            invoke.emit(
              DirectCall(root, [
                ObjectConstant(holder.instantiate([actual]), {}),
                const Constant.integer(41),
              ]),
            ),
          ),
        );
        return machine.run(
          IrFunction(FunctionTarget(null, 'test', .integer, []), [invoke]),
          [],
        ) as int;
      }

      expect(call(ValueType.integer), 41);
      expect(call(ValueType.object.nullable), -1);
      expect(() => call(ValueType.boolean), throwsA(isA<TypeError>()));
    },
  );
}
