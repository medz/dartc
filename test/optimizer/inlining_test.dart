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

void main() {
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
    final rewritten = inlineDirectCalls(program, [
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
        .integer,
      ]);
      final body = Block(helper.parameterTypes);
      body.emit(
        IntBinary(.multiply, body.parameters[1], const Constant.integer(9)),
      );
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
      final result = inlineDirectCalls(program, [root]);
      expect(result, isNot(same(program)));
      for (final input in [program, result]) {
        final events = <int>[];
        expect(_run(input, root, [], events), 6);
        expect(events, [1, 2, 3]);
      }
      expect((result.implementationOf(root) as IrFunction).callees, {_tick});
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
      final result = inlineDirectCalls(program, [root], maxCalleeCost: 32);
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
      final result = inlineDirectCalls(program, [
        root,
        unhandled,
      ], maxCalleeCost: 32);
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
    final result = inlineDirectCalls(program, [root]);
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
      final result = inlineDirectCalls(program, [root]);
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
    final helper = FunctionTarget(_uri, 'identity', .integer, [.integer]);
    final identity = IrFunction(helper, [
      Block(helper.parameterTypes)..finish(Return(const Constant.integer(5))),
    ]);
    final root = FunctionTarget(_uri, 'root', .integer, []);
    IrFunction calls(FunctionTarget target) {
      final entry = Block();
      final a = entry.emit(DirectCall(helper, [const Constant.integer(1)]));
      final b = entry.emit(DirectCall(helper, [a]));
      entry.finish(Return(entry.emit(DirectCall(helper, [b]))));
      return IrFunction(target, [entry]);
    }

    final unused = calls(FunctionTarget(_uri, 'unused', .integer, []));
    final program = IrProgram([], [identity, calls(root), unused]);
    expect(inlineDirectCalls(program, [root], maxCalleeCost: 1), same(program));
    expect(
      inlineDirectCalls(program, [root], maxCallerGrowth: 0),
      same(program),
    );
    expect(
      () => inlineDirectCalls(program, [root], maxCallerGrowth: -1),
      throwsRangeError,
    );
    final result = inlineDirectCalls(program, [root], maxCallerGrowth: 2);
    expect(_run(result, root, []), 5);
    expect(
      (result.implementationOf(root) as IrFunction).entry.instructions
          .whereType<DirectCall>()
          .length,
      2,
    );
    expect(result.implementationOf(unused.target), same(unused));
  });

  test(
    'roots and supplied instance types select callers in the current graph',
    () {
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
      expect(inlineDirectCalls(program, [root]), same(program));
      final result = inlineDirectCalls(
        program,
        [root],
        instantiatedTypes: [type],
      );
      expect((result.implementationOf(method) as IrFunction).callees, isEmpty);
      expect(
        result.implementationOf(root),
        same(program.implementationOf(root)),
      );
      expect(
        inlineDirectCalls(result, [root], instantiatedTypes: [type]),
        same(result),
      );
    },
  );

  test('default costs prefer leaf work over calls and allocation', () {
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
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    final called = entry.emit(DirectCall(wrapper, [const Constant.integer(7)]));
    entry.emit(DirectCall(allocate, [const Constant.string('text')]));
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
    final result = inlineDirectCalls(program, [root]);
    expect((result.implementationOf(root) as IrFunction).callees, {
      wrapper,
      allocate,
    });
    expect(
      result.implementationOf(wrapper),
      same(program.implementationOf(wrapper)),
    );
    final events = <int>[];
    expect(_run(result, root, [], events), 8);
    expect(events, [7]);
  });

  test('self recursion and generic callees retain their calls', () {
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
    final program = IrProgram([], [
      IrFunction(identity, [generic]),
      IrFunction(root, [entry]),
      IrFunction(recursive, [loop]),
    ]);
    expect(inlineDirectCalls(program, [root, recursive]), same(program));
    expect(_run(program, root, []), 8);
  });

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
    final result = inlineDirectCalls(program, [root]);
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
            target,
            FunctionType(FfiTypes.int64, [FfiTypes.int64]),
            exceptionalReturn: const Constant.integer(-1),
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
    expect(inlineDirectCalls(program, [root]), same(program));
  });
}
