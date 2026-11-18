import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:call-entry');
  Object? scalar(FlowValue value) => (value.constant as ScalarConstant).value;
  void optimized(
    IrProgram program,
    FunctionTarget target,
    List<FlowValue> arguments,
    List<Object?> runtimeArguments,
    Object? expected,
  ) {
    final facts = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      ProgramBranchSpecialization(),
      ProgramLoopSpecialization(),
      DirectCallInlining(),
    ]).run(program, [(target: target, arguments: arguments)]);
    expect(scalar(facts.returnedBy(target)), expected);
    expect(
      IrInterpreter(facts.program, {}).run(
        facts.program.implementationOf(target)! as IrFunction,
        runtimeArguments,
      ),
      expected,
    );
  }

  test('nested function values enter only their actual adapter with state', () {
    final state = GlobalVariable(uri, 'state', .integer, isLate: true);
    final shape = CallEntryShape(0, .integer, [.integer]);
    final sources = <IrFunction>[], adapters = <IrFunction>[];
    for (var index = 0; index < 3; index++) {
      final source = FunctionTarget(uri, 'source$index', .integer, [.integer]);
      final body = Block(source.parameterTypes);
      body.finish(
        Return(
          body.emit(
            IntBinary(
              .add,
              body.parameters.single,
              Constant.integer(index + 1),
            ),
          ),
        ),
      );
      sources.add(IrFunction(source, [body]));
      final adapter = FunctionTarget(
        uri,
        'adapter$index',
        .integer,
        shape.signature.parameters,
      );
      final entry = Block(adapter.parameterTypes);
      entry.emit(StoreGlobal(state, Constant.integer((index + 1) * 10)));
      entry.finish(
        Return(entry.emit(DirectCall(source, [entry.parameters[1]]))),
      );
      adapters.add(IrFunction(adapter, [entry]));
    }
    final binding = CallEntryBinding(shape, {
      for (var i = 0; i < sources.length; i++)
        sources[i].target: adapters[i].target,
    });
    final holder = ClassType(uri, 'Holder');
    final field = InstanceField(
      holder,
      'function',
      sources.first.target.signature,
      isFinal: true,
    );
    final root = FunctionTarget(uri, 'root', .integer, [.boolean, .integer]);
    final entry = Block(root.parameterTypes), left = Block(), right = Block();
    final join = Block([holder]);
    entry.finish(Branch(entry.parameters.first, Jump(left), Jump(right)));
    left.finish(
      Jump(join, [
        ObjectConstant(holder, {field: FunctionConstant(sources[0].target)}),
      ]),
    );
    right.finish(
      Jump(join, [
        ObjectConstant(holder, {field: FunctionConstant(sources[1].target)}),
      ]),
    );
    final function = join.emit(LoadField(field, join.parameters.single));
    final call = join.emit(
      FunctionCall(
        function,
        [entry.parameters[1]],
        const {},
        const [],
        null,
        binding,
      ),
    );
    join.finish(
      Return(join.emit(IntBinary(.add, call, join.emit(LoadGlobal(state))))),
    );
    final body = IrFunction(root, [entry, left, right, join]);
    final program = IrProgram(
      [
        IrClass(holder, [field]),
      ],
      [body, ...sources, ...adapters],
      globals: [state],
    );
    for (final choice in [true, false]) {
      final expected = choice ? 18 : 29;
      final facts = ProgramFlow(program, [
        (
          target: root,
          arguments: [
            FlowValue.constant(Constant.boolean(choice)),
            FlowValue.constant(const Constant.integer(7)),
          ],
        ),
      ]).facts;
      expect(scalar(facts.returnedBy(root)), expected);
      expect(IrInterpreter(program, {}).run(body, [choice, 7]), expected);
      expect(facts.definitions, contains(adapters[choice ? 0 : 1].target));
      expect(
        facts.definitions,
        isNot(contains(adapters[choice ? 1 : 0].target)),
      );
      expect(facts.definitions, isNot(contains(adapters[2].target)));
      expect(facts.targetsOf(call), {adapters[choice ? 0 : 1].target});
      expect(facts.sourceTargetsOf(call), {sources[choice ? 0 : 1].target});
      optimized(
        program,
        root,
        [
          FlowValue.constant(Constant.boolean(choice)),
          FlowValue.constant(const Constant.integer(7)),
        ],
        [choice, 7],
        expected,
      );
    }
  });

  test('adapter exceptional state reaches the original call handler', () {
    final state = GlobalVariable(uri, 'state', .integer, isLate: true);
    final source = FunctionTarget(uri, 'source', .integer, []);
    final shape = CallEntryShape(0, .integer, []);
    final adapter = FunctionTarget(
      uri,
      'throwingEntry',
      .integer,
      shape.signature.parameters,
    );
    final adapterBlock = Block(adapter.parameterTypes);
    adapterBlock.emit(StoreGlobal(state, const Constant.integer(43)));
    adapterBlock.finish(Throw(const Constant.string('entry failure')));
    final target = FunctionTarget(uri, 'root', .integer, []);
    final entry = Block(), normal = Block(), failed = Block();
    final call = FunctionCall(
      FunctionConstant(source),
      [],
      const {},
      const [],
      null,
      CallEntryBinding(shape, {source: adapter}),
    );
    entry.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(failed)));
    normal.finish(const Return(Constant.integer(0)));
    failed.finish(Return(failed.emit(LoadGlobal(state))));
    final body = IrFunction(target, [entry, normal, failed]);
    final program = IrProgram(
      [],
      [
        IrFunction(source, [
          Block()..finish(const Return(Constant.integer(1))),
        ]),
        IrFunction(adapter, [adapterBlock]),
        body,
      ],
      globals: [state],
    );
    final facts = ProgramFlow(program, [(target: target, arguments: [])]).facts;
    expect(scalar(facts.returnedBy(target)), 43);
    expect(IrInterpreter(program, {}).run(body, []), 43);
    expect(facts.definitions, isNot(contains(source)));
    optimized(program, target, [], [], 43);
  });

  test('adapter receives the original closure and its shared captures', () {
    final state = GlobalVariable(uri, 'adapterWrite', .integer, isLate: true);
    final root = FunctionTarget(uri, 'capture', .integer, []);
    final target = FunctionTarget(
      uri,
      'write',
      .integer,
      [.integer],
      kind: .closure,
      sourceOffset: 1,
      enclosing: root,
      captures: [CellType(.integer)],
    );
    final source = Block(target.parameterTypes);
    source.emit(WriteCell(source.parameters[1], source.parameters[2]));
    source.finish(Return(source.parameters[2]));
    final shape = CallEntryShape(0, .integer, [.integer]);
    final adapter = FunctionTarget(
      uri,
      'closureEntry',
      .integer,
      shape.signature.parameters,
    );
    final entry = Block(adapter.parameterTypes);
    entry.emit(StoreGlobal(state, const Constant.integer(24)));
    final function = entry.emit(
      UncheckedCast(entry.parameters[0], target.signature),
    );
    entry.finish(
      Return(
        entry.emit(
          FunctionCall(
            function,
            [entry.parameters[1]],
            const {},
            const [],
            target,
          ),
        ),
      ),
    );
    final body = Block();
    final cell = body.emit(
      NewCell(CellType(.integer), const Constant.integer(1)),
    );
    final closure = body.emit(MakeClosure(target, [cell]));
    body.emit(
      FunctionCall(
        closure,
        [const Constant.integer(9)],
        const {},
        const [],
        null,
        CallEntryBinding(shape, {target: adapter}),
      ),
    );
    body.finish(
      Return(
        body.emit(
          IntBinary(
            .add,
            body.emit(ReadCell(cell)),
            body.emit(LoadGlobal(state)),
          ),
        ),
      ),
    );
    final outer = IrFunction(root, [body]);
    final program = IrProgram(
      [],
      [
        outer,
        IrFunction(target, [source]),
        IrFunction(adapter, [entry]),
      ],
      globals: [state],
    );
    final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
    expect(scalar(facts.returnedBy(root)), 33);
    expect(IrInterpreter(program, {}).run(outer, []), 33);
    expect(facts.definitions, containsAll([adapter, target]));
    optimized(program, root, [], [], 33);
  });
}
