import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:inlining');
final _tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);

Object? _run(
  IrProgram program,
  FunctionTarget target,
  List<Object?> arguments, [
  List<int>? events,
]) => IrInterpreter(program, {
  (_uri, 'tick'): (value) {
    events?.add(value);
    return value;
  },
}).run(program.implementationOf(target) as IrFunction, arguments);

IrProgram _inline(
  IrProgram program,
  Iterable<FunctionTarget> roots, {
  int maxCalleeCost = 12,
  int maxCallerGrowth = 64,
}) => DirectCallInlining(
  maxCalleeCost: maxCalleeCost,
  maxCallerGrowth: maxCallerGrowth,
).run(ProgramFlow(program, const [], openEntries: roots).facts);

void main() {
  test(
    'inlining retains promoted values across block parameters and returns',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final promoted = PromotedTypeParameterType(t, ValueType.floating);
      final helper = FunctionTarget(
        _uri,
        'promotedDouble',
        .floating,
        [t],
        typeParameters: [t],
      );
      final body = Block(helper.parameterTypes);
      final yes = Block([promoted]), no = Block();
      final test = body.emit(TypeTest(body.parameters.single, promoted));
      body.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
      yes.finish(Return(yes.parameters.single));
      no.finish(const Return(Constant.floating(-1.0)));
      final root = FunctionTarget(_uri, 'root', .floating, [.object.nullable]);
      final entry = Block(root.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            DirectCall(
              helper,
              entry.parameters,
              typeArguments: [.object.nullable],
            ),
          ),
        ),
      );
      final source = IrProgram([], [
        IrFunction(helper, [body, yes, no]),
        IrFunction(root, [entry]),
      ]);
      final result = _inline(source, [root]);
      expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
      for (final value in <Object?>[1.25, -0.0, 42, 'other', null]) {
        expect(_run(result, root, [value]), _run(source, root, [value]));
      }
    },
  );

  test('inlining keeps both runtime obligations of a promoted type test', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final helper = FunctionTarget(
      _uri,
      'check',
      .boolean,
      [.object.nullable],
      typeParameters: [t],
    );
    final body = Block(helper.parameterTypes);
    body.finish(
      Return(
        body.emit(
          TypeTest(
            body.parameters.single,
            PromotedTypeParameterType(t, ValueType.integer),
          ),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .boolean, [.object.nullable]);
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          DirectCall(helper, entry.parameters, typeArguments: [.object]),
        ),
      ),
    );
    final source = IrProgram([], [
      IrFunction(helper, [body]),
      IrFunction(root, [entry]),
    ]);
    final result = _inline(source, [root]);
    expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
    for (final value in <Object?>[3, 'other', 1.25, null]) {
      expect(_run(result, root, [value]), value is int);
    }
  });

  test(
    'instantiated promotions survive fields, cells, calls and exception edges',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final slot = TypeParameterType('V')..initializeBound(.object.nullable);
      final owner = ClassType(_uri, 'Holder', typeParameters: [slot]);
      final field = InstanceField(owner, 'value', slot);
      final initialize = FunctionTarget(
        _uri,
        'new',
        .voidType,
        [slot],
        owner: owner,
        kind: .initializer,
      );
      final initializing = Block(initialize.parameterTypes);
      initializing.emit(
        StoreField(
          field,
          initializing.parameters[0],
          initializing.parameters[1],
        ),
      );
      initializing.finish(const Return());
      final promoted = PromotedTypeParameterType(t, ValueType.integer);
      final helper = FunctionTarget(
        _uri,
        'promotedStorage',
        .integer,
        [.object.nullable],
        typeParameters: [t],
      );
      final body = Block(helper.parameterTypes);
      final checked = body.emit(TypeCast(body.parameters.single, promoted));
      final object = body.emit(
        Construct(initialize, [
          checked,
        ], instantiatedType: owner.instantiate([promoted])),
      );
      final loaded = body.emit(LoadField(field, object));
      final cell = body.emit(NewCell(CellType(promoted), loaded));
      final read = body.emit(ReadCell(cell));
      final called = body.emit(DirectCall(_tick, [read]));
      body.finish(
        Return(body.emit(IntBinary(.add, called, const Constant.integer(1)))),
      );
      final root = FunctionTarget(_uri, 'root', .integer, [.object.nullable]);
      final entry = Block(root.parameterTypes),
          done = Block([ValueType.integer]),
          failed = Block();
      final call = DirectCall(
        helper,
        entry.parameters,
        typeArguments: [.object],
      );
      entry.finish(
        Invoke(call, onReturn: Jump(done, [call]), onThrow: Jump(failed)),
      );
      done.finish(Return(done.parameters.single));
      failed.finish(const Return(Constant.integer(-99)));
      final helperBody = IrFunction(helper, [body]);
      final rootBody = IrFunction(root, [entry, done, failed]);
      final source = IrProgram(
        [
          IrClass(owner, [field], constructors: [initialize]),
        ],
        [
          IrFunction(initialize, [initializing]),
          helperBody,
          rootBody,
        ],
        externals: [IrExternal(_tick)],
      );
      // Exercise copying these consumers independently of the inlining cost
      // policy; the smaller promoted-return case above uses the default pass.
      final rewritten = FunctionRewrite(
        rootBody,
        inlined: {
          call: (
            body: helperBody,
            arguments: entry.parameters,
            environment: {t: ValueType.object},
            handler: (entry.end as Invoke).onThrow,
          ),
        },
      ).run();
      final result = IrProgram(source.classes, [
        for (final function in source.functions)
          function.target == root ? rewritten : function,
      ], externals: source.externals);
      expect(
        (result.implementationOf(root) as IrFunction).callees,
        isNot(contains(helper)),
      );
      for (final value in <Object?>[7, -13, 'bad', null]) {
        final before = <int>[], after = <int>[];
        expect(
          _run(result, root, [value], after),
          _run(source, root, [value], before),
        );
        expect(after, before);
        expect(after, value is int ? [value] : isEmpty);
      }
    },
  );

  test(
    'inlined type reification retains the lexical type without its proof',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final helper = FunctionTarget(
        _uri,
        'reified',
        .typeType,
        [],
        typeParameters: [t],
      );
      final body = Block();
      body.finish(
        Return(
          body.emit(ReifyType(PromotedTypeParameterType(t, ValueType.integer))),
        ),
      );
      final root = FunctionTarget(_uri, 'root', .typeType, []);
      final entry = Block();
      entry.finish(
        Return(entry.emit(DirectCall(helper, [], typeArguments: [.object]))),
      );
      final source = IrProgram([], [
        IrFunction(helper, [body]),
        IrFunction(root, [entry]),
      ]);
      final result = _inline(source, [root]);
      expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
      expect(_run(result, root, []), _run(source, root, []));
    },
  );

  test('inlining preserves call-bound frame values at the remaining call', () {
    final walker = FunctionTarget(_uri, 'walk', .integer, [.integer, .integer]);
    final helper = FunctionTarget(_uri, 'helper', .integer, []);
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final call = DirectCall(walker, [
      CallFrameValue.stackPointer,
      CallFrameValue.returnAddress,
    ]);
    final body = Block();
    body.finish(Return(body.emit(call)));
    final entry = Block();
    entry.finish(Return(entry.emit(DirectCall(helper, []))));
    final walkerBody = Block(walker.parameterTypes);
    walkerBody.finish(Return(walkerBody.parameters.first));
    final result = _inline(
      IrProgram([], [
        IrFunction(root, [entry]),
        IrFunction(helper, [body]),
        IrFunction(walker, [walkerBody]),
      ]),
      [root],
    );
    final retained = (result.implementationOf(root) as IrFunction).blocks
        .expand((block) => block.instructions)
        .whereType<DirectCall>()
        .single;
    expect(retained.target, walker);
    expect(retained.inputs, [
      CallFrameValue.stackPointer,
      CallFrameValue.returnAddress,
    ]);
  });

  test('unused call-frame arguments do not block inlining or lose effects', () {
    final callee = FunctionTarget(_uri, 'ignoreFrames', .integer, [
      .integer,
      .integer,
      .integer,
    ]);
    final body = Block(callee.parameterTypes);
    body.finish(
      Return(
        body.emit(
          IntBinary(.add, body.parameters.last, const Constant.integer(1)),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'entry', .integer, []);
    final entry = Block();
    final observed = entry.emit(DirectCall(_tick, [const Constant.integer(7)]));
    entry.finish(
      Return(
        entry.emit(
          DirectCall(callee, [
            CallFrameValue.stackPointer,
            CallFrameValue.returnAddress,
            observed,
          ]),
        ),
      ),
    );
    final program = IrProgram(
      [],
      [
        IrFunction(root, [entry]),
        IrFunction(callee, [body]),
      ],
      externals: [IrExternal(_tick)],
    );
    final result = ProgramOptimizer(const [
      ProgramSimplification(),
      DirectCallInlining(),
    ]).run(program, [(target: root, arguments: [])]).program;
    final events = <int>[];
    expect(_run(result, root, [], events), 8);
    expect(events, [7]);
    expect(result.implementationOf(root)!.callees, {_tick});
  });

  test('pure call chains expand from leaves within one caller budget', () {
    final leaf = FunctionTarget(_uri, 'leaf', .integer, [.integer]);
    final middle = FunctionTarget(_uri, 'middle', .integer, [.integer]);
    final root = FunctionTarget(_uri, 'root', .integer, [.integer]);
    final last = Block(leaf.parameterTypes);
    final added = last.emit(
      IntBinary(.add, last.parameters.single, const Constant.integer(1)),
    );
    last.finish(
      Return(last.emit(IntBinary(.multiply, added, const Constant.integer(2)))),
    );
    IrFunction forward(FunctionTarget target, FunctionTarget callee) {
      final block = Block(target.parameterTypes);
      block.finish(Return(block.emit(DirectCall(callee, block.parameters))));
      return IrFunction(target, [block]);
    }

    final bodies = [
      forward(root, middle),
      forward(middle, leaf),
      IrFunction(leaf, [last]),
    ];
    for (final order in [bodies, bodies.reversed.toList()]) {
      final program = IrProgram([], order);
      final after = _inline(program, [root]);
      expect((after.implementationOf(root) as IrFunction).callees, isEmpty);
      for (final input in [-7, 0, 42]) {
        expect(_run(after, root, [input]), _run(program, root, [input]));
      }
      final bounded = _inline(program, [root], maxCallerGrowth: 1);
      expect((bounded.implementationOf(root) as IrFunction).callees, {leaf});
    }
  });

  test(
    'actual call inputs shrink shared bodies before applying the budget',
    () {
      final helper = FunctionTarget(_uri, 'shared', .integer, [
        .boolean,
        .integer,
      ]);
      final choosing = Block(helper.parameterTypes),
          short = Block(),
          long = Block();
      choosing.finish(Branch(choosing.parameters[0], Jump(long), Jump(short)));
      short.finish(
        Return(
          short.emit(
            IntBinary(.add, choosing.parameters[1], const Constant.integer(2)),
          ),
        ),
      );
      for (var i = 0; i < 13; i++) {
        long.emit(DirectCall(_tick, [Constant.integer(i)]));
      }
      long.finish(Return(choosing.parameters[1]));
      IrFunction caller(String name, bool noisy) {
        final target = FunctionTarget(_uri, name, .integer, [.integer]);
        final entry = Block(target.parameterTypes);
        entry.finish(
          Return(
            entry.emit(
              DirectCall(helper, [
                Constant.boolean(noisy),
                entry.parameters.single,
              ]),
            ),
          ),
        );
        return IrFunction(target, [entry]);
      }

      final quiet = caller('quiet', false), noisy = caller('noisy', true);
      final program = IrProgram(
        [],
        [
          quiet,
          noisy,
          IrFunction(helper, [choosing, short, long]),
        ],
        externals: [
          IrExternal(_tick, effects: {Effect.writesStorage}),
        ],
      );
      final after = _inline(program, [quiet.target, noisy.target, helper]);
      expect(
        (after.implementationOf(quiet.target) as IrFunction).callees,
        isEmpty,
      );
      expect((after.implementationOf(noisy.target) as IrFunction).callees, {
        helper,
      });
      for (final value in [-9, 0, 41]) {
        for (final graph in [program, after]) {
          final events = <int>[];
          expect(_run(graph, quiet.target, [value], events), value + 2);
          expect(events, isEmpty);
          expect(_run(graph, noisy.target, [value], events), value);
          expect(events, List.generate(13, (index) => index));
          events.clear();
          expect(_run(graph, helper, [false, value], events), value + 2);
          expect(events, isEmpty);
          expect(_run(graph, helper, [true, value], events), value);
          expect(events, List.generate(13, (index) => index));
        }
      }
    },
  );

  test('a non-returning invocation keeps its proof after CFG expansion', () {
    final helper = FunctionTarget(_uri, 'chooseOrThrow', .integer, [.boolean]);
    final branch = Block(helper.parameterTypes),
        returns = Block(),
        fails = Block();
    branch.finish(Branch(branch.parameters.single, Jump(returns), Jump(fails)));
    returns.finish(const Return(Constant.integer(7)));
    fails.finish(Throw(const Constant.string('failure')));
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    final call = entry.emit(
      DirectCall(helper, [const Constant.boolean(false)]),
    );
    entry.finish(Unreachable(call));
    final program = IrProgram([], [
      IrFunction(helper, [branch, returns, fails]),
      IrFunction(root, [entry]),
    ]);
    final optimized = _inline(program, [root], maxCalleeCost: 32);
    final body = optimized.implementationOf(root) as IrFunction;
    expect(body.callees, isNot(contains(helper)));
    for (final graph in [program, optimized]) {
      expect(() => _run(graph, root, []), throwsA('failure'));
    }
  });

  test('cleanup retains caller and inlined lifetime markers after calls', () {
    final helper = FunctionTarget(_uri, 'retain', .voidType, [.object]);
    final body = Block(helper.parameterTypes);
    body.emit(DirectCall(_tick, [const Constant.integer(1)]));
    body.emit(KeepAlive(body.parameters.single));
    body.finish(const Return());
    final root = FunctionTarget(_uri, 'root', .integer, [.object]);
    final entry = Block(root.parameterTypes);
    entry.emit(
      IntBinary(.add, const Constant.integer(1), const Constant.integer(2)),
    );
    entry.emit(DirectCall(helper, entry.parameters));
    final result = entry.emit(DirectCall(_tick, [const Constant.integer(2)]));
    entry.emit(KeepAlive(entry.parameters.single));
    entry.finish(Return(result));
    final program = IrProgram(
      [],
      [
        IrFunction(helper, [body]),
        IrFunction(root, [entry]),
      ],
      externals: [IrExternal(_tick)],
    );
    final rewritten = _inline(program, [
      root,
    ], maxCalleeCost: 32).implementationOf(root) as IrFunction;
    expect(rewritten.callees, {_tick});
    expect(rewritten.entry.instructions.map((op) => op.runtimeType), [
      DirectCall,
      KeepAlive,
      DirectCall,
      KeepAlive,
    ]);
    for (final marker in rewritten.entry.instructions.whereType<KeepAlive>()) {
      expect(marker.value, same(rewritten.entry.parameters.single));
    }
  });

  test(
    'arguments and effects execute once in order, including unused inputs',
    () {
      final helper = FunctionTarget(_uri, 'first', .integer, [
        .integer,
        .object,
      ]);
      final body = Block(helper.parameterTypes);
      body.finish(
        Return(
          body.emit(
            IntBinary(.add, body.parameters[0], const Constant.integer(1)),
          ),
        ),
      );
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block();
      final a = entry.emit(DirectCall(_tick, [const Constant.integer(1)]));
      final b = entry.emit(DirectCall(_tick, [const Constant.integer(2)]));
      final first = entry.emit(DirectCall(helper, [a, b]));
      final c = entry.emit(DirectCall(_tick, [const Constant.integer(3)]));
      final second = entry.emit(DirectCall(helper, [c, a]));
      entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
      final program = IrProgram(
        [],
        [
          IrFunction(helper, [body]),
          IrFunction(root, [entry]),
        ],
        externals: [IrExternal(_tick)],
      );
      final facts = CallTypeFlow(program, [root]).facts;
      final result = _inline(program, [root]);
      expect(result, isNot(same(program)));
      for (final input in [program, result]) {
        final events = <int>[];
        expect(_run(input, root, [], events), 6);
        expect(events, [1, 2, 3]);
      }
      expect((result.implementationOf(root) as IrFunction).callees, {_tick});
      expect(
        (result.implementationOf(root) as IrFunction).blocks
            .expand((block) => block.instructions)
            .whereType<TypeView>(),
        isEmpty,
      );
      expect(CallTypeFlow(result, [root]).facts.definitions, {root, _tick});
      expect(() => facts.checkProgram(result), throwsArgumentError);
      expect(facts.definitions, contains(helper));
      expect(
        (program.implementationOf(root) as IrFunction).callees,
        contains(helper),
      );
    },
  );

  test(
    'instance fields and string results use the same direct-call transform',
    () {
      final type = ClassType(_uri, 'Label');
      final field = InstanceField(type, 'text', .string, isFinal: true);
      final helper = FunctionTarget(
        _uri,
        'append',
        .string,
        [.string],
        owner: type,
        kind: .method,
      );
      final body = Block(helper.parameterTypes);
      final text = body.emit(LoadField(field, body.parameters.first));
      body.finish(Return(body.emit(StringConcat(text, body.parameters[1]))));
      final root = FunctionTarget(_uri, 'root', .string, []);
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            DirectCall(helper, [
              ObjectConstant(type, {field: const Constant.string('left')}),
              const Constant.string('right'),
            ]),
          ),
        ),
      );
      final program = IrProgram(
        [
          IrClass(type, [field], members: [helper]),
        ],
        [
          IrFunction(helper, [body]),
          IrFunction(root, [entry]),
        ],
      );
      final result = _inline(program, [root], maxCalleeCost: 32);
      expect(_run(program, root, []), 'leftright');
      expect(_run(result, root, []), 'leftright');
      expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
    },
  );

  test(
    'inlined throwing operations retain the handler, trace and source position',
    () {
      final helper = FunctionTarget(_uri, 'check', .integer, [.object]);
      final body = Block(helper.parameterTypes);
      body.emit(DirectCall(_tick, [const Constant.integer(1)]));
      final cast = body.emit(TypeCast(body.parameters.single, .string));
      body.emit(DirectCall(_tick, [const Constant.integer(2)]));
      body.finish(const Return(Constant.integer(7)));
      final location = SourceLocation((uri: _uri, line: 12, column: 4));
      final root = FunctionTarget(_uri, 'root', .integer, [.object]);
      final entry = Block(root.parameterTypes),
          normal = Block([ValueType.integer]);
      final caught = Block([ValueType.object, ValueType.stackTrace]);
      final call = DirectCall(helper, entry.parameters);
      entry.finish(
        Invoke(
          call,
          onReturn: Jump(normal, [call]),
          onThrow: Jump(caught, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
          ]),
        ),
      );
      normal.finish(Return(normal.parameters.single));
      caught.emit(DirectCall(_tick, [const Constant.integer(9)]));
      caught.finish(const Return(Constant.integer(-1)));
      final unhandled = FunctionTarget(_uri, 'unhandled', .integer, [.object]);
      final uncaught = Block(unhandled.parameterTypes);
      uncaught.finish(
        Return(uncaught.emit(DirectCall(helper, uncaught.parameters))),
      );
      final program = IrProgram(
        [],
        [
          IrFunction(helper, [body], sourceLocations: {cast: location}),
          IrFunction(root, [entry, caught, normal]),
          IrFunction(unhandled, [uncaught]),
        ],
        externals: [IrExternal(_tick)],
      );
      final result = _inline(program, [root, unhandled], maxCalleeCost: 32);
      for (final input in [program, result]) {
        final events = <int>[];
        expect(_run(input, root, [42], events), -1);
        expect(events, [1, 9]);
        events.clear();
        expect(_run(input, root, ['ok'], events), 7);
        expect(events, [1, 2]);
        events.clear();
        expect(
          () => _run(input, unhandled, [42], events),
          throwsA(isA<TypeError>()),
        );
        expect(events, [1]);
      }
      final rewritten = result.implementationOf(root) as IrFunction;
      expect(rewritten.callees, {_tick});
      final copiedCast = rewritten.blocks
          .map((b) => b.end)
          .whereType<Invoke>()
          .map((end) => end.operation)
          .whereType<TypeCast>()
          .single;
      final origin = rewritten.sourceLocations[copiedCast]!;
      expect(origin.position, location.position);
      expect(origin.function, same(helper));
      expect(origin.caller!.position, isNull);
      expect(origin.caller!.caller, isNull);
    },
  );

  test('loop parameters and non-topological blocks remain valid', () {
    final helper = FunctionTarget(_uri, 'next', .integer, [.integer]);
    final body = Block(helper.parameterTypes);
    body.finish(
      Return(
        body.emit(
          IntBinary(.add, body.parameters.single, const Constant.integer(1)),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'sum', .integer, [.integer]);
    final entry = Block(root.parameterTypes),
        loop = Block([ValueType.integer, ValueType.integer]);
    final step = Block(), done = Block();
    entry.finish(
      Jump(loop, [const Constant.integer(0), const Constant.integer(0)]),
    );
    loop.finish(
      Branch(
        loop.emit(
          IntBinary(.lessThan, loop.parameters[0], entry.parameters.single),
        ),
        Jump(step),
        Jump(done),
      ),
    );
    final next = step.emit(DirectCall(helper, [loop.parameters[0]]));
    final sum = step.emit(
      IntBinary(.add, loop.parameters[1], loop.parameters[0]),
    );
    step.finish(Jump(loop, [next, sum]));
    done.finish(Return(loop.parameters[1]));
    final program = IrProgram([], [
      IrFunction(helper, [body]),
      IrFunction(root, [entry, done, step, loop]),
    ]);
    final result = _inline(program, [root]);
    for (final count in [0, 1, 5, 12]) {
      expect(_run(result, root, [count]), _run(program, root, [count]));
    }
    expect(_run(result, root, [5]), 10);
    expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
  });

  test(
    'constant branch cleanup removes dead calls and callback registrations',
    () {
      final state = ClassType(_uri, 'State');
      final drain = FunctionTarget(_uri, 'drain', .voidType, [state, .boolean]);
      final callback = InstanceField(
        state,
        'callback',
        drain.signature.nullable,
      );
      final initialize = FunctionTarget(
        _uri,
        'new',
        .voidType,
        [],
        owner: state,
        kind: .initializer,
      );
      final helper = FunctionTarget(_uri, 'enabled', .boolean, []);
      final predicate = IrFunction(helper, [
        Block()..finish(const Return(Constant.boolean(true))),
      ]);
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block(), yes = Block(), no = Block();
      entry.finish(
        Branch(entry.emit(DirectCall(helper, [])), Jump(yes), Jump(no)),
      );
      yes.finish(const Return(Constant.integer(11)));
      no.emit(
        StoreField(
          callback,
          no.emit(Construct(initialize, [])),
          FunctionConstant(drain),
        ),
      );
      no.finish(
        Return(no.emit(DirectCall(_tick, [const Constant.integer(99)]))),
      );
      final program = IrProgram(
        [
          IrClass(state, [callback], constructors: [initialize]),
        ],
        [
          predicate,
          IrFunction(initialize, [
            Block(initialize.parameterTypes)..finish(const Return()),
          ]),
          IrFunction(drain, [
            Block(drain.parameterTypes)..finish(const Return()),
          ]),
          IrFunction(root, [entry, yes, no]),
        ],
        externals: [IrExternal(_tick)],
      );
      final facts = CallTypeFlow(program, [root]).facts;
      expect(facts.definitions, {root, helper, _tick, initialize, drain});
      final result = _inline(program, [root]);
      final events = <int>[];
      expect(_run(result, root, [], events), 11);
      expect(events, isEmpty);
      expect(CallTypeFlow(result, [root]).facts.definitions, {root});
      expect(reachableDefinitions(result, [root]), {root});
      expect(result.functions.length, program.functions.length);
      expect(result.implementationOf(helper), same(predicate));
    },
  );

  test('cost bounds and selected callers limit expansion without changing semantics', () {
    final helper = FunctionTarget(_uri, 'increment', .integer, [.integer]);
    final body = Block(helper.parameterTypes);
    body.finish(
      Return(
        body.emit(
          IntBinary(.add, body.parameters.single, const Constant.integer(1)),
        ),
      ),
    );
    final increment = IrFunction(helper, [body]);
    final root = FunctionTarget(_uri, 'root', .integer, [.integer]);
    IrFunction calls(FunctionTarget target) {
      final entry = Block(target.parameterTypes);
      final a = entry.emit(DirectCall(helper, [entry.parameters.single]));
      final b = entry.emit(DirectCall(helper, [a]));
      entry.finish(Return(entry.emit(DirectCall(helper, [b]))));
      return IrFunction(target, [entry]);
    }

    final unused = calls(FunctionTarget(_uri, 'unused', .integer, [.integer]));
    final program = IrProgram([], [increment, calls(root), unused]);
    expect(_inline(program, [root], maxCalleeCost: 0), same(program));
    expect(_inline(program, [root], maxCallerGrowth: 0), same(program));
    expect(
      () => _inline(program, [root], maxCallerGrowth: -1),
      throwsRangeError,
    );
    final result = _inline(program, [root], maxCallerGrowth: 2);
    expect(_run(result, root, [1]), 4);
    expect(
      (result.implementationOf(root) as IrFunction).entry.instructions
          .whereType<DirectCall>()
          .length,
      1,
    );
    expect(result.implementationOf(unused.target), same(unused));
  });

  test('entry arguments select virtual callers in the current graph', () {
    final type = ClassType(_uri, 'Box');
    final helper = FunctionTarget(_uri, 'value', .integer, []);
    final method = FunctionTarget(
      _uri,
      'read',
      .integer,
      [],
      owner: type,
      kind: .method,
    );
    final methodBody = Block(method.parameterTypes);
    methodBody.finish(Return(methodBody.emit(DirectCall(helper, []))));
    final root = FunctionTarget(_uri, 'root', .integer, [type]);
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(entry.emit(InstanceCall(method, entry.parameters.single, []))),
    );
    final program = IrProgram(
      [
        IrClass(type, [], members: [method]),
      ],
      [
        IrFunction(helper, [
          Block()..finish(const Return(Constant.integer(5))),
        ]),
        IrFunction(method, [methodBody]),
        IrFunction(root, [entry]),
      ],
    );
    final result = _inline(program, [root]);
    expect((result.implementationOf(method) as IrFunction).callees, isEmpty);
    expect(result.implementationOf(root), same(program.implementationOf(root)));
    expect(_inline(result, [root]), same(result));
  });

  test('default expansion preserves calls and removes unused allocations', () {
    final wrapper = FunctionTarget(_uri, 'wrapper', .integer, [.integer]);
    final forwarding = Block(wrapper.parameterTypes);
    forwarding.finish(
      Return(forwarding.emit(DirectCall(_tick, forwarding.parameters))),
    );
    final allocate = FunctionTarget(_uri, 'append', .string, [.string]);
    final allocation = Block(allocate.parameterTypes);
    allocation.finish(
      Return(
        allocation.emit(
          StringConcat(
            allocation.parameters.single,
            const Constant.string('!'),
          ),
        ),
      ),
    );
    final leaf = FunctionTarget(_uri, 'next', .integer, [.integer]);
    final arithmetic = Block(leaf.parameterTypes);
    arithmetic.finish(
      Return(
        arithmetic.emit(
          IntBinary(
            .add,
            arithmetic.parameters.single,
            const Constant.integer(1),
          ),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .integer, [.string]);
    final entry = Block(root.parameterTypes);
    final called = entry.emit(DirectCall(wrapper, [const Constant.integer(7)]));
    entry.emit(DirectCall(allocate, entry.parameters));
    entry.finish(Return(entry.emit(DirectCall(leaf, [called]))));
    final program = IrProgram(
      [],
      [
        IrFunction(wrapper, [forwarding]),
        IrFunction(allocate, [allocation]),
        IrFunction(leaf, [arithmetic]),
        IrFunction(root, [entry]),
      ],
      externals: [IrExternal(_tick)],
    );
    final result = _inline(program, [root]);
    final rewritten = result.implementationOf(root) as IrFunction;
    expect(rewritten.callees, {_tick});
    expect(
      rewritten.blocks
          .expand((block) => block.instructions)
          .whereType<StringConcat>(),
      isEmpty,
    );
    expect(
      result.implementationOf(wrapper),
      same(program.implementationOf(wrapper)),
    );
    final events = <int>[];
    expect(_run(result, root, ['text'], events), 8);
    expect(events, [7]);
  });

  test(
    'generic callees use actual binders while self recursion stays a call',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final identity = FunctionTarget(
        _uri,
        'identity',
        t,
        [t],
        typeParameters: [t],
      );
      final generic = Block(identity.parameterTypes);
      generic.finish(Return(generic.parameters.single));
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            DirectCall(
              identity,
              [const Constant.integer(8)],
              typeArguments: [ValueType.integer],
            ),
          ),
        ),
      );
      final recursive = FunctionTarget(_uri, 'recursive', .integer, [.integer]);
      final loop = Block(recursive.parameterTypes);
      loop.finish(Return(loop.emit(DirectCall(recursive, loop.parameters))));
      final caller = FunctionTarget(_uri, 'caller', .integer, [.integer]);
      final call = Block(caller.parameterTypes);
      call.finish(Return(call.emit(DirectCall(recursive, call.parameters))));
      final program = IrProgram([], [
        IrFunction(identity, [generic]),
        IrFunction(root, [entry]),
        IrFunction(recursive, [loop]),
        IrFunction(caller, [call]),
      ]);
      final result = _inline(program, [root, caller]);
      expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
      expect((result.implementationOf(recursive) as IrFunction).callees, {
        recursive,
      });
      expect(_run(result, root, []), 8);
      expect(
        result.implementationOf(caller),
        same(program.implementationOf(caller)),
      );
      expect(_inline(result, [root, caller]), same(result));
    },
  );

  test('void calls retain their actual return values', () {
    final helper = FunctionTarget(_uri, 'voidValue', .voidType, []);
    final root = FunctionTarget(_uri, 'root', .voidType, []);
    final body = Block()..finish(const Return(Constant.string('kept')));
    final entry = Block();
    entry.finish(Return(entry.emit(DirectCall(helper, []))));
    final program = IrProgram([], [
      IrFunction(helper, [body]),
      IrFunction(root, [entry]),
    ]);
    final result = _inline(program, [root]);
    expect(_run(program, root, []), 'kept');
    expect(_run(result, root, []), 'kept');
    expect((result.implementationOf(root) as IrFunction).callees, isEmpty);
  });

  test('callback-producing helpers retain one native address site', () {
    final target = FunctionTarget(_uri, 'callback', .integer, [.integer]);
    final callback = Block(target.parameterTypes)
      ..finish(const Return(Constant.integer(0)));
    final helper = FunctionTarget(_uri, 'callbackAddress', .integer, []);
    final body = Block();
    body.finish(
      Return(
        body.emit(
          NativeCallbackAddress(
            StaticCallbackTarget(
              target,
              FunctionType(FfiTypes.int64, [FfiTypes.int64]),
              exceptionalReturn: const Constant.integer(-1),
            ),
          ),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .boolean, []);
    final entry = Block();
    final left = entry.emit(DirectCall(helper, []));
    final right = entry.emit(DirectCall(helper, []));
    entry.finish(Return(entry.emit(Identical(left, right))));
    final program = IrProgram([], [
      IrFunction(target, [callback]),
      IrFunction(helper, [body]),
      IrFunction(root, [entry]),
    ]);
    final rewritten = _inline(program, [root]);
    expect(_run(program, root, []), isTrue);
    expect(_run(rewritten, root, []), isTrue);
    expect(
      (rewritten.implementationOf(root) as IrFunction).callees,
      isNot(contains(helper)),
    );
  });
}
