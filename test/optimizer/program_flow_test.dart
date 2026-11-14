import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:program-flow');

void main() {
  test(
    'constant control flow excludes calls and unobserved function bodies',
    () {
      final tick = FunctionTarget(_uri, 'tick', .integer, []);
      final unused = FunctionTarget(_uri, 'unused', .integer, []);
      final unusedBlock = Block();
      unusedBlock.finish(Return(unusedBlock.emit(DirectCall(tick, []))));
      final entry = Block();
      final live = Block();
      final dead = Block();
      final condition = entry.emit(
        Equals(const Constant.integer(1), const Constant.integer(2)),
      );
      entry.finish(Branch(condition, Jump(dead), Jump(live)));
      dead.finish(Return(dead.emit(DirectCall(unused, []))));
      final pool = SequenceConstant(
        CoreTypes.listOf(FunctionType(.integer, [])),
        [FunctionConstant(unused)],
      );
      final length = live.emit(CollectionLength(pool));
      live.finish(
        Return(live.emit(IntBinary(.add, length, const Constant.integer(6)))),
      );
      final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
        live,
        dead,
      ]);
      final program = IrProgram(
        [],
        [
          main,
          IrFunction(unused, [unusedBlock]),
        ],
        externals: [IrExternal(tick)],
      );
      final facts = _flow(program, main).facts;
      expect(IrInterpreter(program, {}).run(main, []), 7);
      expect(
        facts.returnedBy(main.target).constant?.structuralKey,
        const Constant.integer(7).structuralKey,
      );
      expect(facts.definitions, {main.target});
      expect(facts.reachesBlock(dead), isFalse);
      expect(
        facts.valueOf(condition).constant?.structuralKey,
        const Constant.boolean(false).structuralKey,
      );
    },
  );

  test(
    'normalized nullable dispatch preserves its result and actual failure',
    () {
      final owner = ClassType(_uri, 'NullableReceiver');
      final method = FunctionTarget(
        _uri,
        'answer',
        .integer,
        [],
        owner: owner,
        kind: .method,
      );
      final answer = Block(method.parameterTypes)
        ..finish(const Return(Constant.integer(7)));
      final failure = FunctionTarget(null, 'missing', .dynamicType, [
        .dynamicType,
      ]);
      final failed = Block(failure.parameterTypes)
        ..finish(Throw(const Constant.integer(41)));
      final entry = Block([owner.nullable]);
      final call = entry.emit(
        DynamicDispatch(
          entry.parameters.single,
          method.selector,
          [],
          const {},
          const [],
          failure,
        ),
      );
      entry.finish(Return(call));
      final main = IrFunction(
        FunctionTarget(_uri, 'nullable', .dynamicType, [owner.nullable]),
        [entry],
      );
      final program = IrProgram(
        [
          IrClass(owner, [], members: [method]),
        ],
        [
          main,
          IrFunction(method, [answer]),
          IrFunction(failure, [failed]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: main.target, arguments: [FlowValue.unknown(owner.nullable)]),
      ]).facts;
      expect(
        facts.returnedBy(main.target).constant?.structuralKey,
        const Constant.integer(7).structuralKey,
      );
      expect(
        facts.thrownBy(main.target).exception.constant?.structuralKey,
        const Constant.integer(41).structuralKey,
      );
      expect(facts.targetsOf(call), unorderedEquals([method, failure]));
    },
  );

  test('function arguments and returned values select actual call targets', () {
    final add = _addOne();
    final other = _constant('other', 99, parameters: [.integer]);
    final type = FunctionType(.integer, [.integer]);
    final relayTarget = FunctionTarget(_uri, 'relay', type, [type]);
    // The returned function is data until the caller invokes it.
    final returning = Block(relayTarget.parameterTypes);
    returning.finish(Return(returning.parameters.single));
    final mainBlock = Block();
    final returned = mainBlock.emit(
      DirectCall(relayTarget, [FunctionConstant(add.target)]),
    );
    final call = mainBlock.emit(
      FunctionCall(returned, [const Constant.integer(3)]),
    );
    mainBlock.finish(Return(call));
    final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      mainBlock,
    ]);
    final program = IrProgram([], [
      main,
      add,
      other,
      IrFunction(relayTarget, [returning]),
    ]);
    final facts = _flow(program, main).facts;
    expect(IrInterpreter(program, {}).run(main, []), 4);
    expect(facts.targetsOf(call), {add.target});
    expect(facts.hasUnknownCall(call), isFalse);
    expect(facts.definitions, isNot(contains(other.target)));
    expect(
      facts.valueOf(call).constant?.structuralKey,
      const Constant.integer(4).structuralKey,
    );
  });

  test(
    'different invocations do not rewrite the shared body from one caller',
    () {
      final add = _addOne();
      final entry = Block();
      final first = entry.emit(
        DirectCall(add.target, [const Constant.integer(1)]),
      );
      final second = entry.emit(
        DirectCall(add.target, [const Constant.integer(8)]),
      );
      entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
      final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
      ]);
      final program = IrProgram([], [main, add]);
      final facts = _flow(program, main).facts;
      expect(IrInterpreter(program, {}).run(main, []), 11);
      expect(
        facts.valueOf(first).constant?.structuralKey,
        const Constant.integer(2).structuralKey,
      );
      expect(
        facts.valueOf(second).constant?.structuralKey,
        const Constant.integer(9).structuralKey,
      );
      expect(facts.activationsOf(add.target), hasLength(2));
      expect(facts.valueOf(add.entry.parameters.single).constant, isNull);
      expect(facts.canDiscard(first), isTrue);
    },
  );

  test('loop values reschedule consumers across parameterless edges', () {
    final target = FunctionTarget(_uri, 'sum', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final loop = Block([ValueType.integer, ValueType.integer]);
    final body = Block();
    final done = Block();
    final exit = Block();
    entry.finish(
      Jump(loop, [const Constant.integer(0), const Constant.integer(0)]),
    );
    loop.finish(
      Branch(
        loop.emit(
          IntBinary(.lessThan, loop.parameters.first, entry.parameters.single),
        ),
        Jump(body),
        Jump(done),
      ),
    );
    final sum = body.emit(
      IntBinary(.add, loop.parameters.last, loop.parameters.first),
    );
    final next = body.emit(
      IntBinary(.add, loop.parameters.first, const Constant.integer(1)),
    );
    body.finish(Jump(loop, [next, sum]));
    done.finish(Jump(exit));
    exit.finish(Return(loop.parameters.last));
    final function = IrFunction(target, [entry, loop, body, done, exit]);
    final program = IrProgram([], [function]);
    final facts = _flow(program, function, [FlowValue.unknown(.integer)]).facts;
    expect(IrInterpreter(program, {}).run(function, [0]), 0);
    expect(IrInterpreter(program, {}).run(function, [5]), 10);
    expect(facts.valueOf(next).constant, isNull);
    expect(facts.valueOf(sum).constant, isNull);
    expect(facts.returnedBy(target).constant, isNull);
    expect(facts.returnedBy(target).unknownTypes, contains(ValueType.integer));
  });

  test('repeated semantic inputs do not expand every call path', () {
    final functions = <IrFunction>[];
    var child = FunctionTarget(_uri, 'leaf', .integer, [.integer]);
    final leaf = Block(child.parameterTypes);
    leaf.finish(Return(leaf.parameters.single));
    functions.add(IrFunction(child, [leaf]));
    for (var depth = 0; depth < 12; depth++) {
      final parent = FunctionTarget(_uri, 'level$depth', .integer, [.integer]);
      final block = Block(parent.parameterTypes);
      final left = block.emit(DirectCall(child, [block.parameters.single]));
      final right = block.emit(DirectCall(child, [block.parameters.single]));
      block.finish(Return(block.emit(IntBinary(.add, left, right))));
      functions.add(IrFunction(parent, [block]));
      child = parent;
    }
    final program = IrProgram([], functions);
    final facts = _flow(program, functions.last, [
      FlowValue.unknown(.integer),
    ]).facts;
    expect(IrInterpreter(program, {}).run(functions.last, [3]), 3 * 4096);
    for (final function in functions) {
      expect(facts.activationsOf(function.target), hasLength(1));
    }
  });

  test('a shared summary substitutes each callers own SSA argument', () {
    final identity = FunctionTarget(_uri, 'identity', .integer, [.integer]);
    final body = Block(identity.parameterTypes);
    body.finish(Return(body.parameters.single));
    final target = FunctionTarget(_uri, 'main', .integer, [.integer, .integer]);
    final entry = Block(target.parameterTypes);
    final first = entry.emit(DirectCall(identity, [entry.parameters.first]));
    final second = entry.emit(DirectCall(identity, [entry.parameters.last]));
    entry.finish(Return(entry.emit(IntBinary(.subtract, first, second))));
    final main = IrFunction(target, [entry]);
    final program = IrProgram([], [
      main,
      IrFunction(identity, [body]),
    ]);
    final facts = _flow(program, main, [
      FlowValue.unknown(.integer),
      FlowValue.unknown(.integer),
    ]).facts;
    expect(IrInterpreter(program, {}).run(main, [11, 4]), 7);
    expect(facts.activationsOf(identity), hasLength(1));
    expect(facts.equivalentsOf(first), contains(entry.parameters.first));
    expect(facts.equivalentsOf(first), isNot(contains(entry.parameters.last)));
    expect(facts.equivalentsOf(second), contains(entry.parameters.last));
    expect(
      facts.equivalentsOf(second),
      isNot(contains(entry.parameters.first)),
    );
  });

  test('summary reuse returns distinct fresh objects and preserves private caller storage', () {
    final box = ClassType(_uri, 'Box');
    final field = InstanceField(box, 'value', .integer);
    final initializer = FunctionTarget(
      _uri,
      '',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    final init = Block(initializer.parameterTypes);
    init.emit(
      StoreField(field, init.parameters.single, const Constant.integer(0)),
    );
    init.finish(const Return());
    final factory = FunctionTarget(_uri, 'makeBox', box, []);
    final make = Block();
    make.finish(Return(make.emit(Construct(initializer, []))));
    final entry = Block();
    final first = entry.emit(DirectCall(factory, []));
    final second = entry.emit(DirectCall(factory, []));
    entry.emit(StoreField(field, first, const Constant.integer(7)));
    final read = entry.emit(LoadField(field, second));
    entry.finish(Return(read));
    final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
    ]);
    final program = IrProgram(
      [
        IrClass(box, [field], constructors: [initializer]),
      ],
      [
        main,
        IrFunction(factory, [make]),
        IrFunction(initializer, [init]),
      ],
    );
    final facts = _flow(program, main).facts;
    expect(IrInterpreter(program, {}).run(main, []), 0);
    expect(facts.activationsOf(factory), hasLength(1));
    final original = facts.returnedBy(factory).objects.single;
    final firstObject = facts.valueOf(first).objects.single;
    final secondObject = facts.valueOf(second).objects.single;
    expect(facts.mayAliasAcrossSummaries(original, firstObject), isTrue);
    expect(facts.mayAliasAcrossSummaries(secondObject, original), isTrue);
    expect(facts.mayAliasAcrossSummaries(firstObject, firstObject), isTrue);
    expect(facts.mayAliasAcrossSummaries(firstObject, secondObject), isFalse);
    expect(
      facts.valueOf(first).objects.single,
      isNot(facts.valueOf(second).objects.single),
    );
    expect(
      facts.valueOf(read).constant?.structuralKey,
      const Constant.integer(0).structuralKey,
    );
  });

  test(
    'implicit member calls propagate actual arguments and storage effects',
    () {
      final collection = ClassType(
        _uri,
        'ObservedList',
        interfaces: [CoreTypes.listOf(.integer)],
      );
      final length = FunctionTarget(
        _uri,
        'length',
        .integer,
        [],
        owner: collection,
        kind: .getter,
      );
      final initializer = FunctionTarget(
        _uri,
        '',
        .voidType,
        [],
        owner: collection,
        kind: .initializer,
      );
      final global = GlobalVariable(_uri, 'observed', .integer, isLate: true);
      final getter = Block(length.parameterTypes);
      getter.emit(StoreGlobal(global, const Constant.integer(9)));
      getter.finish(const Return(Constant.integer(2)));
      final entry = Block();
      entry.emit(StoreGlobal(global, const Constant.integer(3)));
      final object = entry.emit(Construct(initializer, []));
      final measured = entry.emit(CollectionLength(object));
      final observed = entry.emit(LoadGlobal(global));
      entry.finish(Return(entry.emit(IntBinary(.add, measured, observed))));
      final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
      ]);
      final program = IrProgram(
        [
          IrClass(
            collection,
            [],
            constructors: [initializer],
            members: [length],
          ),
        ],
        [
          main,
          IrFunction(initializer, [
            Block(initializer.parameterTypes)..finish(const Return()),
          ]),
          IrFunction(length, [getter]),
        ],
        globals: [global],
      );
      final facts = _flow(program, main).facts;
      expect(
        facts.valueOf(observed).constant?.structuralKey,
        const Constant.integer(9).structuralKey,
      );
      expect(
        facts.returnedBy(main.target).constant?.structuralKey,
        const Constant.integer(11).structuralKey,
      );
      expect(facts.targetsOf(measured), {length});
      expect(facts.effectsOf(measured), contains(Effect.writesStorage));
    },
  );

  test('a closure reads the same captured cell after its overwrite', () {
    final mainTarget = FunctionTarget(_uri, 'main', .integer, []);
    final cellType = CellType(.integer);
    final target = FunctionTarget(
      _uri,
      'captured',
      .integer,
      [],
      kind: .closure,
      enclosing: mainTarget,
      sourceOffset: 1,
      captures: [cellType],
    );
    final closureBody = Block(target.parameterTypes);
    final captured = closureBody.emit(ReadCell(closureBody.parameters[1]));
    closureBody.finish(
      Return(
        closureBody.emit(IntBinary(.add, captured, const Constant.integer(1))),
      ),
    );
    final entry = Block();
    final cell = entry.emit(NewCell(cellType, const Constant.integer(1)));
    final closure = entry.emit(MakeClosure(target, [cell]));
    entry.emit(WriteCell(cell, const Constant.integer(7)));
    final call = entry.emit(FunctionCall(closure, []));
    entry.finish(Return(call));
    final main = IrFunction(mainTarget, [entry]);
    final program = IrProgram([], [
      main,
      IrFunction(target, [closureBody]),
    ]);
    final facts = _flow(program, main).facts;
    expect(IrInterpreter(program, {}).run(main, []), 8);
    expect(facts.targetsOf(call), {target});
    expect(
      facts.valueOf(call).constant?.structuralKey,
      const Constant.integer(8).structuralKey,
    );
  });

  test('storage preserves the original unknown SSA value', () {
    final target = FunctionTarget(_uri, 'sameValue', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final original = entry.parameters.single;
    final cell = entry.emit(NewCell(CellType(.integer), original));
    final load = entry.emit(ReadCell(cell));
    entry.finish(Return(load));
    final main = IrFunction(target, [entry]);
    final program = IrProgram([], [main]);
    final facts = _flow(program, main, [FlowValue.unknown(.integer)]).facts;
    final activation = facts.activationsOf(target).single;
    expect(IrInterpreter(program, {}).run(main, [43]), 43);
    expect(facts.valueOf(load).constant, isNull);
    expect(
      facts.valueOf(load).sources,
      contains(FlowSource(original, activation)),
    );
    final point = facts.pointStateOf(load)!;
    point.before.invalidate([facts.valueOf(cell)]);
    expect(
      facts.valueOf(load).sources,
      contains(FlowSource(original, activation)),
    );
    expect(facts.reachesOperation(load), isTrue);
  });

  test(
    'an actual thrown value survives a call and the exceptional CFG edge',
    () {
      final throwing = FunctionTarget(_uri, 'throwing', .integer, []);
      final body = Block()..finish(Throw(const Constant.string('fault')));
      final entry = Block();
      final success = Block([ValueType.integer]);
      final handler = Block([ValueType.object, ValueType.stackTrace]);
      final call = DirectCall(throwing, []);
      entry.finish(
        Invoke(
          call,
          onReturn: Jump(success, [call]),
          onThrow: Jump(handler, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
          ]),
        ),
      );
      success.finish(
        Return(success.emit(TypeView(success.parameters.single, .object))),
      );
      handler.finish(Return(handler.parameters.first));
      final main = IrFunction(FunctionTarget(_uri, 'main', .object, []), [
        entry,
        success,
        handler,
      ]);
      final program = IrProgram([], [
        main,
        IrFunction(throwing, [body]),
      ]);
      final facts = _flow(program, main).facts;
      expect(IrInterpreter(program, {}).run(main, []), 'fault');
      expect(facts.reachesBlock(success), isFalse);
      expect(
        facts.valueOf(handler.parameters.first).constant?.structuralKey,
        const Constant.string('fault').structuralKey,
      );
      expect(
        facts.failureOf(call).exception.constant?.structuralKey,
        const Constant.string('fault').structuralKey,
      );
      expect(
        facts.thrownBy(throwing).exception.constant?.structuralKey,
        const Constant.string('fault').structuralKey,
      );
      expect(facts.edgeStateOf((entry.end as Invoke).onThrow), isNotNull);
    },
  );

  test(
    'only an explicitly escaping return opens its actual function value',
    () {
      final used = _constant('used', 7);
      final unused = _constant('unused', 11);
      final entry = Block()..finish(Return(FunctionConstant(used.target)));
      final main = IrFunction(
        FunctionTarget(_uri, 'main', used.target.signature, []),
        [entry],
      );
      final program = IrProgram([], [main, used, unused]);
      final closed = _flow(program, main).facts;
      expect(closed.definitions, {main.target});
      final open = ProgramFlow(
        program,
        [(target: main.target, arguments: <FlowValue>[])],
        escapingReturns: [main.target],
      ).facts;
      expect(open.definitions, {main.target, used.target});
      expect(
        open.returnedBy(used.target).constant?.structuralKey,
        const Constant.integer(7).structuralKey,
      );
    },
  );

  test('a throwing callee returns state written before its exception', () {
    final global = GlobalVariable(_uri, 'saved', .integer, isLate: true);
    final target = FunctionTarget(_uri, 'writeThenThrow', .voidType, []);
    final throwing = Block();
    throwing.emit(StoreGlobal(global, const Constant.integer(7)));
    throwing.finish(Throw(const Constant.string('failure')));
    final entry = Block();
    entry.emit(StoreGlobal(global, const Constant.integer(1)));
    final success = Block()..finish(const Return(Constant.integer(0)));
    final handler = Block();
    final read = handler.emit(LoadGlobal(global));
    handler.finish(Return(read));
    final call = DirectCall(target, []);
    final goodEdge = Jump(success);
    final badEdge = Jump(handler);
    entry.finish(Invoke(call, onReturn: goodEdge, onThrow: badEdge));
    final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
      success,
      handler,
    ]);
    final program = IrProgram(
      [],
      [
        main,
        IrFunction(target, [throwing]),
      ],
      globals: [global],
    );
    final facts = _flow(program, main).facts;
    expect(IrInterpreter(program, {}).run(main, []), 7);
    expect(facts.exitsOf(call), (normal: false, exceptional: true));
    expect(facts.reachesEdge(goodEdge), isFalse);
    expect(facts.reachesEdge(badEdge), isTrue);
    expect(
      facts.valueOf(read).constant?.structuralKey,
      const Constant.integer(7).structuralKey,
    );
    expect(facts.canDiscard(call), isFalse);
  });

  test('a possibly returning pure loop is not a discardable call', () {
    final target = FunctionTarget(_uri, 'maybeSpin', .voidType, [.boolean]);
    final body = Block(target.parameterTypes);
    final returning = Block()..finish(const Return());
    final loop = Block();
    loop.finish(Jump(loop));
    body.finish(Branch(body.parameters.single, Jump(returning), Jump(loop)));
    final entry = Block([.boolean]);
    final call = entry.emit(DirectCall(target, entry.parameters));
    entry.finish(const Return());
    final main = IrFunction(
      FunctionTarget(_uri, 'main', .voidType, [.boolean]),
      [entry],
    );
    final program = IrProgram([], [
      main,
      IrFunction(target, [body, returning, loop]),
    ]);
    final facts = _flow(program, main, [FlowValue.unknown(.boolean)]).facts;
    expect(facts.exitsOf(call).normal, isTrue);
    expect(facts.effectsOf(call), isEmpty);
    expect(facts.canDiscard(call), isFalse);
  });

  test('recursive executions converge without claiming termination', () {
    final target = FunctionTarget(_uri, 'recurse', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final zero = Block()..finish(const Return(Constant.integer(0)));
    final again = Block([.integer]);
    entry.finish(
      Branch(
        entry.emit(Equals(entry.parameters.single, const Constant.integer(0))),
        Jump(zero),
        Jump(again, entry.parameters),
      ),
    );
    final next = again.emit(
      IntBinary(.subtract, again.parameters.single, const Constant.integer(1)),
    );
    final call = again.emit(DirectCall(target, [next]));
    again.finish(Return(call));
    final body = IrFunction(target, [entry, zero, again]);
    final facts = _flow(IrProgram([], [body]), body, [
      FlowValue.unknown(.integer),
    ]).facts;
    expect(facts.activationsOf(target), hasLength(1));
    expect(
      facts.returnedBy(target).constant?.structuralKey,
      const Constant.integer(0).structuralKey,
    );
    expect(facts.canDiscard(call), isFalse);
  });

  test('new entry arguments invalidate equal-sized old facts', () {
    final add = _addOne();
    final program = IrProgram([], [add]);
    final flow = _flow(program, add, [
      FlowValue.constant(const Constant.integer(1)),
    ]);
    final old = flow.facts;
    expect(
      flow.extend(
        entries: [
          (
            target: add.target,
            arguments: [FlowValue.constant(const Constant.integer(8))],
          ),
        ],
      ),
      isTrue,
    );
    expect(() => old.returnedBy(add.target), throwsStateError);
    expect(flow.facts.returnedBy(add.target).constant, isNull);
    expect(
      flow.extend(
        entries: [
          (
            target: add.target,
            arguments: [FlowValue.constant(const Constant.integer(8))],
          ),
        ],
      ),
      isFalse,
    );
    expect(
      () => flow.facts.checkProgram(IrProgram([], [add])),
      throwsArgumentError,
    );
  });

  test('entry and query operands cannot import another graph activation', () {
    final target = FunctionTarget(_uri, 'entry', .voidType, [
      ValueType.object.nullable,
    ]);
    final block = Block(target.parameterTypes)..finish(const Return());
    final body = IrFunction(target, [block]);
    final program = IrProgram([], [body]);
    final foreignType = ClassType(_uri, 'Foreign');
    final foreign = Construct(
      FunctionTarget(
        _uri,
        'new',
        .voidType,
        [],
        owner: foreignType,
        kind: .initializer,
      ),
      [],
    );
    expect(
      () => _flow(program, body, [
        FlowValue.object(FlowObject(foreign, Object())),
      ]),
      throwsArgumentError,
    );
    final facts = _flow(program, body, [
      FlowValue.unknown(ValueType.object.nullable),
    ]).facts;
    expect(() => facts.valueOf(foreign), throwsArgumentError);
    expect(facts.owns(block.parameters.single), isTrue);
    expect(facts.owns(const Constant.integer(7)), isTrue);
    expect(facts.owns(foreign), isFalse);
    final foreignTest = TypeTest(block.parameters.single, foreignType);
    final refinement = foreignTest.refinement(true)!;
    expect(facts.owns(refinement), isFalse);
    expect(() => facts.valueOf(refinement), throwsArgumentError);
    expect(() => facts.equivalentsOf(refinement), throwsArgumentError);
  });

  test(
    'foreign calls only expose actual callback values and reachable state',
    () {
      final global = GlobalVariable(_uri, 'saved', .integer, isLate: true);
      final callbackType = FunctionType(.voidType, []);
      final callbackTarget = FunctionTarget(_uri, 'callback', .voidType, []);
      final callback = Block();
      callback.emit(StoreGlobal(global, const Constant.integer(3)));
      callback.finish(const Return());
      final unused = FunctionTarget(
        _uri,
        'sameSignatureButPrivate',
        .voidType,
        [],
      );
      final external = FunctionTarget(_uri, 'external', .voidType, [
        callbackType,
      ]);
      final entry = Block();
      entry.emit(StoreGlobal(global, const Constant.integer(2)));
      final call = entry.emit(
        DirectCall(external, [FunctionConstant(callbackTarget)]),
      );
      final read = entry.emit(LoadGlobal(global));
      entry.finish(Return(read));
      final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
      ]);
      final program = IrProgram(
        [],
        [
          main,
          IrFunction(callbackTarget, [callback]),
          IrFunction(unused, [Block()..finish(const Return())]),
        ],
        globals: [global],
        externals: [IrExternal(external)],
      );
      final facts = _flow(program, main).facts;
      expect(facts.definitions, contains(callbackTarget));
      expect(facts.definitions, isNot(contains(unused)));
      expect(facts.valueOf(read).constant, isNull);
      expect(facts.canDiscard(call), isFalse);
    },
  );

  for (final raw in [false, true]) {
    test('external capture access follows raw address capability ($raw)', () {
      final add = _addOne();
      final mainTarget = FunctionTarget(_uri, 'main', .voidType, []);
      final callbackTarget = FunctionTarget(
        _uri,
        'callback',
        .integer,
        [],
        kind: .closure,
        enclosing: mainTarget,
        sourceOffset: 2,
        captures: [add.target.signature],
      );
      final callbackBody = Block(callbackTarget.parameterTypes);
      callbackBody.finish(
        Return(
          callbackBody.emit(
            FunctionCall(callbackBody.parameters[1], [
              const Constant.integer(7),
            ]),
          ),
        ),
      );
      final boundaryType = raw ? ValueType.integer : callbackTarget.signature;
      final external = FunctionTarget(_uri, 'accept', boundaryType, [
        boundaryType,
      ]);
      final entry = Block();
      final callback = entry.emit(
        MakeClosure(callbackTarget, [FunctionConstant(add.target)]),
      );
      final argument = raw ? entry.emit(ReferenceAddress(callback)) : callback;
      final returned = entry.emit(DirectCall(external, [argument]));
      entry.emit(DirectCall(external, [returned]));
      entry.finish(const Return());
      final main = IrFunction(mainTarget, [entry]);
      final program = IrProgram(
        [],
        [
          main,
          add,
          IrFunction(callbackTarget, [callbackBody]),
        ],
        externals: [IrExternal(external)],
      );
      final facts = _flow(program, main).facts;
      expect(
        facts.valueOf(add.entry.parameters.single).constant?.structuralKey,
        raw ? null : const Constant.integer(7).structuralKey,
      );
      expect(
        facts.returnedBy(add.target).constant?.structuralKey,
        raw ? null : const Constant.integer(8).structuralKey,
      );
    });
  }

  test('a definite write after a callback boundary replaces the earlier captured value', () {
    final mainTarget = FunctionTarget(_uri, 'main', .integer, []);
    final cellType = CellType(.integer);
    final callbackTarget = FunctionTarget(
      _uri,
      'callback',
      .integer,
      [],
      kind: .closure,
      enclosing: mainTarget,
      sourceOffset: 3,
      captures: [cellType],
    );
    final callbackBody = Block(callbackTarget.parameterTypes);
    callbackBody.finish(
      Return(callbackBody.emit(ReadCell(callbackBody.parameters[1]))),
    );
    final external = FunctionTarget(_uri, 'accept', .voidType, [
      callbackTarget.signature,
    ]);
    final entry = Block();
    final cell = entry.emit(NewCell(cellType, const Constant.integer(1)));
    final callback = entry.emit(MakeClosure(callbackTarget, [cell]));
    entry.emit(DirectCall(external, [callback]));
    entry.emit(WriteCell(cell, const Constant.integer(7)));
    final read = entry.emit(ReadCell(cell));
    entry.finish(Return(read));
    final main = IrFunction(mainTarget, [entry]);
    final program = IrProgram(
      [],
      [
        main,
        IrFunction(callbackTarget, [callbackBody]),
      ],
      externals: [IrExternal(external)],
    );
    final facts = _flow(program, main).facts;
    expect(
      facts.valueOf(read).constant?.structuralKey,
      const Constant.integer(7).structuralKey,
    );
  });

  test('an explicit leaf contract does not invent callback execution or termination', () {
    final global = GlobalVariable(_uri, 'private', .integer, isLate: true);
    final callback = FunctionTarget(_uri, 'callback', .voidType, []);
    final callbackBody = Block();
    callbackBody.emit(StoreGlobal(global, const Constant.integer(99)));
    callbackBody.finish(const Return());
    final leaf = FunctionTarget(_uri, 'leaf', .voidType, [callback.signature]);
    final entry = Block();
    entry.emit(StoreGlobal(global, const Constant.integer(3)));
    final call = entry.emit(DirectCall(leaf, [FunctionConstant(callback)]));
    final load = entry.emit(LoadGlobal(global));
    entry.finish(Return(load));
    final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
    ]);
    final program = IrProgram(
      [],
      [
        main,
        IrFunction(callback, [callbackBody]),
      ],
      globals: [global],
      externals: [IrExternal(leaf, effects: const {})],
    );
    final facts = _flow(program, main).facts;
    expect(
      facts.valueOf(load).constant?.structuralKey,
      const Constant.integer(3).structuralKey,
    );
    expect(facts.definitions, isNot(contains(callback)));
    expect(facts.effectsOf(call), isEmpty);
    expect(facts.exitsOf(call), (normal: true, exceptional: false));
    expect(facts.canDiscard(call), isFalse);
  });

  test(
    'an external call without reachable storage leaves a private binding known',
    () {
      final global = GlobalVariable(_uri, 'private', .integer, isLate: true);
      final external = FunctionTarget(_uri, 'external', .voidType, []);
      final entry = Block();
      entry.emit(StoreGlobal(global, const Constant.integer(2)));
      entry.emit(DirectCall(external, []));
      final read = entry.emit(LoadGlobal(global));
      entry.finish(Return(read));
      final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
      ]);
      final facts = _flow(
        IrProgram(
          [],
          [main],
          globals: [global],
          externals: [IrExternal(external)],
        ),
        main,
      ).facts;
      expect(
        facts.valueOf(read).constant?.structuralKey,
        const Constant.integer(2).structuralKey,
      );
      expect(facts.canDiscard(read), isTrue);
    },
  );
}

ProgramFlow _flow(
  IrProgram program,
  IrFunction entry, [
  List<FlowValue> arguments = const [],
]) => ProgramFlow(program, [(target: entry.target, arguments: arguments)]);

IrFunction _constant(
  String name,
  int value, {
  List<ValueType> parameters = const [],
}) {
  final target = FunctionTarget(_uri, name, .integer, parameters);
  return IrFunction(target, [
    Block(target.parameterTypes)..finish(Return(Constant.integer(value))),
  ]);
}

IrFunction _addOne() {
  final target = FunctionTarget(_uri, 'addOne', .integer, [.integer]);
  final body = Block(target.parameterTypes);
  body.finish(
    Return(
      body.emit(
        IntBinary(.add, body.parameters.single, const Constant.integer(1)),
      ),
    ),
  );
  return IrFunction(target, [body]);
}
