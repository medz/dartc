import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/runtime/contracts.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:call-access');

void main() {
  for (final recursive in [false, true]) {
    test(
      'entry references exclude fresh getter inputs (recursive=$recursive)',
      () {
        final node = ClassType(_uri, 'Node');
        final field = InstanceField(node, 'value', .integer);
        final initialize = FunctionTarget(
          _uri,
          '',
          .voidType,
          [.integer],
          owner: node,
          kind: .initializer,
        );
        final init = Block(initialize.parameterTypes);
        init.emit(
          StoreField(field, init.parameters.first, init.parameters.last),
        );
        init.finish(const Return());
        final getter = FunctionTarget(_uri, 'get', .integer, [node]);
        final read = Block(getter.parameterTypes);
        read.finish(
          Return(read.emit(LoadField(field, read.parameters.single))),
        );
        final root = FunctionTarget(_uri, 'walk', .integer, [node, .integer]);
        final head = Block(root.parameterTypes),
            again = Block(),
            done = Block();
        const depth = 8;
        if (recursive) {
          head.finish(
            Branch(
              head.emit(
                Equals(head.parameters.last, const Constant.integer(0)),
              ),
              Jump(done),
              Jump(again),
            ),
          );
          done.finish(
            Return(done.emit(DirectCall(getter, [head.parameters.first]))),
          );
          final fresh = again.emit(
            Construct(initialize, [head.parameters.last]),
          );
          final original = again.emit(
            DirectCall(getter, [head.parameters.first]),
          );
          final tail = again.emit(
            DirectCall(root, [
              head.parameters.first,
              again.emit(
                IntBinary(
                  .subtract,
                  head.parameters.last,
                  const Constant.integer(1),
                ),
              ),
            ]),
          );
          final own = again.emit(LoadField(field, fresh));
          again.finish(
            Return(
              again.emit(
                IntBinary(
                  .add,
                  original,
                  again.emit(IntBinary(.add, tail, own)),
                ),
              ),
            ),
          );
        } else {
          Value sum = const Constant.integer(0);
          for (var i = 0; i < depth; i++) {
            final fresh = head.emit(
              Construct(initialize, [Constant.integer(i)]),
            );
            final original = head.emit(
              DirectCall(getter, [head.parameters.first]),
            );
            final own = head.emit(LoadField(field, fresh));
            sum = head.emit(
              IntBinary(.add, sum, head.emit(IntBinary(.add, original, own))),
            );
          }
          head.finish(Return(sum));
        }
        final oracle = FunctionTarget(_uri, 'oracle', .integer, []);
        final concrete = Block();
        final receiver = concrete.emit(
          Construct(initialize, [const Constant.integer(3)]),
        );
        concrete.finish(
          Return(
            concrete.emit(
              DirectCall(root, [receiver, const Constant.integer(depth)]),
            ),
          ),
        );
        final program = IrProgram(
          [
            IrClass(node, [field], constructors: [initialize]),
          ],
          [
            IrFunction(initialize, [init]),
            IrFunction(getter, [read]),
            IrFunction(root, [
              head,
              if (recursive) ...[again, done],
            ]),
            IrFunction(oracle, [concrete]),
          ],
        );
        final facts = ProgramFlow(program, [
          (
            target: root,
            arguments: [
              FlowValue.unknown(node),
              FlowValue.constant(const Constant.integer(depth)),
            ],
          ),
        ]).facts;
        // Recursive calls retain the solver's separate repeated-execution
        // context; neither context depends on the private allocations.
        expect(facts.activationsOf(getter), hasLength(recursive ? 2 : 1));
        final expected = recursive ? 63 : 52;
        expect(facts.returnedBy(root).integers!.contains(expected), isTrue);
        for (final graph in [
          program,
          const ProgramSimplification().run(facts),
        ]) {
          expect(
            IrInterpreter(
              graph,
              {},
            ).run(graph.implementationOf(oracle) as IrFunction, []),
            expected,
          );
        }
      },
    );
  }

  for (final throwsAfterWrite in [false, true]) {
    test(
      'external writes connect fresh aliases on both exits ($throwsAfterWrite)',
      () {
        final node = ClassType(_uri, 'ConnectedNode');
        final holder = ClassType(_uri, 'Holder');
        final field = InstanceField(node, 'value', .integer);
        final child = InstanceField(holder, 'child', node);
        final connect = FunctionTarget(_uri, 'connect', .voidType, [
          holder,
          node,
        ]);
        final store = Block(connect.parameterTypes);
        store.emit(
          StoreField(child, store.parameters.first, store.parameters.last),
        );
        store.finish(
          throwsAfterWrite ? Throw(const Constant.integer(7)) : const Return(),
        );
        final getter = FunctionTarget(_uri, 'getChild', node, [holder]);
        final read = Block(getter.parameterTypes);
        read.finish(
          Return(read.emit(LoadField(child, read.parameters.single))),
        );
        final setter = FunctionTarget(_uri, 'setChildValue', .voidType, [node]);
        final write = Block(setter.parameterTypes);
        write.emit(
          StoreField(field, write.parameters.single, const Constant.integer(9)),
        );
        write.finish(const Return());
        final root = FunctionTarget(_uri, 'connectRoot', .integer, [holder]);
        final entry = Block(root.parameterTypes), continuation = Block();
        final fresh = entry.emit(NewPayload(node, const Constant.integer(0)));
        entry.emit(StoreField(field, fresh, const Constant.integer(1)));
        entry.finish(
          Invoke(
            DirectCall(connect, [entry.parameters.single, fresh]),
            onReturn: Jump(continuation),
            onThrow: Jump(continuation),
          ),
        );
        final alias = continuation.emit(DirectCall(getter, entry.parameters));
        continuation.emit(DirectCall(setter, [alias]));
        continuation.finish(Return(continuation.emit(LoadField(field, fresh))));
        final oracle = FunctionTarget(_uri, 'connectedOracle', .integer, []);
        final concrete = Block();
        final receiver = concrete.emit(
          NewPayload(holder, const Constant.integer(0)),
        );
        concrete.finish(Return(concrete.emit(DirectCall(root, [receiver]))));
        final program = IrProgram(
          [
            IrClass(node, [field]),
            IrClass(holder, [child]),
          ],
          [
            IrFunction(root, [entry, continuation]),
            IrFunction(oracle, [concrete]),
            IrFunction(connect, [store]),
            IrFunction(getter, [read]),
            IrFunction(setter, [write]),
          ],
        );
        final facts = ProgramFlow(program, [
          (target: root, arguments: [FlowValue.unknown(holder)]),
        ]).facts;
        expect(facts.valueOf(alias).externalUnknownTypes, contains(node));
        expect(facts.returnedBy(root).constant, isNull);
        expect(facts.returnedBy(root).integers!.contains(9), isTrue);
        for (final graph in [
          program,
          const ProgramSimplification().run(facts),
        ]) {
          expect(
            IrInterpreter(
              graph,
              {},
            ).run(graph.implementationOf(oracle) as IrFunction, []),
            9,
          );
        }
      },
    );
  }

  group('input access dependencies', _inputAccessDependencies);
  test('mixed constant and unknown fields retain the other branch state', () {
    final box = ClassType(_uri, 'Mixed');
    final flag = InstanceField(box, 'flag', .boolean, isFinal: true);
    final observed = GlobalVariable(_uri, 'observed', .integer, isLate: true);
    final callback = FunctionTarget(_uri, 'opaque', .voidType, []);
    final helper = FunctionTarget(_uri, 'helper', .integer, [box]);
    final head = Block(helper.parameterTypes), yes = Block(), no = Block();
    head.finish(
      Branch(
        head.emit(LoadField(flag, head.parameters.single)),
        Jump(yes),
        Jump(no),
      ),
    );
    yes.finish(const Return(Constant.integer(7)));
    final loaded = no.emit(LoadGlobal(observed));
    no.emit(DirectCall(callback, []));
    no.finish(Return(loaded));
    final root = FunctionTarget(_uri, 'root', .integer, [box]);
    final entry = Block(root.parameterTypes);
    entry.emit(StoreGlobal(observed, const Constant.integer(9)));
    entry.finish(Return(entry.emit(DirectCall(helper, entry.parameters))));
    final oracle = FunctionTarget(_uri, 'oracle', .integer, []);
    final oracleBody = Block();
    oracleBody.finish(
      Return(
        oracleBody.emit(
          DirectCall(root, [
            ObjectConstant(box, {flag: const Constant.boolean(false)}),
          ]),
        ),
      ),
    );
    final program = IrProgram(
      [
        IrClass(box, [flag]),
      ],
      [
        IrFunction(root, [entry]),
        IrFunction(helper, [head, yes, no]),
        IrFunction(oracle, [oracleBody]),
      ],
      globals: [observed],
      externals: [IrExternal(callback)],
    );
    final facts = ProgramFlow(program, [
      (
        target: root,
        arguments: [
          FlowValue.constant(
            ObjectConstant(box, {flag: const Constant.boolean(true)}),
          ).join(FlowValue.unknown(box)),
        ],
      ),
    ]).facts;
    expect(facts.definitions, contains(callback));
    final range = facts.returnedBy(root).integers!;
    expect(range.lower, lessThanOrEqualTo(7));
    expect(range.upper, greaterThanOrEqualTo(9));
    final simplified = const ProgramSimplification().run(facts);
    for (final graph in [program, simplified]) {
      // The concrete alternative supplies the value admitted by the unknown arm.
      final interpreted = IrInterpreter(
        graph,
        {},
        externalCalls: {callback: (_) => null},
      );
      expect(
        interpreted.run(graph.implementationOf(oracle) as IrFunction, []),
        9,
      );
    }
  });

  for (final metadata in [false, true]) {
    test(
      'immutable constant fields select access dependencies ($metadata)',
      () {
        const count = 16;
        final box = ClassType(_uri, 'Choice');
        final flag = InstanceField(box, 'flag', .boolean, isFinal: true);
        final callback = FunctionTarget(_uri, 'opaque', .voidType, []);
        final helper = FunctionTarget(_uri, 'helper', .integer, [
          metadata ? ValueType.typeType : box,
        ]);
        final head = Block(helper.parameterTypes), yes = Block(), no = Block();
        final read = head.emit(
          LoadField(
            metadata ? TypeMetadata.kind : flag,
            metadata
                ? head.emit(
                    UncheckedCast(head.parameters.single, TypeMetadata.type),
                  )
                : head.parameters.single,
          ),
        );
        final condition = metadata
            ? head.emit(Equals(read, Constant.integer(TypeKind.nominal.index)))
            : read;
        head.finish(Branch(condition, Jump(yes), Jump(no)));
        yes.finish(const Return(Constant.integer(7)));
        no.emit(DirectCall(callback, []));
        no.finish(const Return(Constant.integer(9)));
        final noise = [
          for (var i = 0; i < count; i++)
            GlobalVariable(_uri, 'noise$i', ValueType.integer.nullable),
        ];
        final root = FunctionTarget(_uri, 'root', .integer, []);
        final entry = Block();
        final Constant receiver = metadata
            ? TypeConstant(.integer)
            : ObjectConstant(box, {flag: const Constant.boolean(true)});
        Value sum = const Constant.integer(0);
        for (var i = 0; i < count; i++) {
          entry.emit(StoreGlobal(noise[i], Constant.integer(i)));
          final call = entry.emit(DirectCall(helper, [receiver]));
          sum = entry.emit(IntBinary(.add, sum, call));
        }
        entry.finish(Return(sum));
        final program = IrProgram(
          [
            IrClass(box, [flag]),
            for (final entry in TypeMetadata.fields.entries)
              IrClass(entry.key, entry.value),
          ],
          [
            IrFunction(root, [entry]),
            IrFunction(helper, [head, yes, no]),
          ],
          globals: noise,
          externals: [IrExternal(callback)],
        );
        final layout = ProgramLayout(
          program.classes,
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        );
        final facts = ProgramFlow(program, [
          (target: root, arguments: <FlowValue>[]),
        ], memoryLayout: layout).facts;
        expect(_number(facts.returnedBy(root)), count * 7);
        expect(facts.activationsOf(helper), hasLength(1));
        expect(facts.definitions, isNot(contains(callback)));
        final simplified = const ProgramSimplification().run(facts);
        for (final graph in [program, simplified]) {
          expect(
            IrInterpreter(
              graph,
              {},
              typeLayout: layout,
            ).run(graph.implementationOf(root) as IrFunction, []),
            count * 7,
          );
        }
      },
    );
  }
  test('actual receivers exclude an unselected opaque implementation', () {
    final fixture = _dispatch();
    final facts = ProgramFlow(fixture.program, [
      (target: fixture.root, arguments: [fixture.known]),
    ]).facts;
    expect(_number(facts.returnedBy(fixture.root)), 112);
    expect(facts.activationsOf(fixture.helper), hasLength(1));
    expect(facts.activationsOf(fixture.pure), hasLength(1));
    expect(facts.activationsOf(fixture.opaque), isEmpty);
  });

  test(
    'widened receiver inputs restore opaque access and runtime alternatives',
    () {
      final fixture = _dispatch();
      final flow = ProgramFlow(fixture.program, [
        (target: fixture.root, arguments: [fixture.known]),
      ]);
      expect(_number(flow.facts.returnedBy(fixture.root)), 112);
      flow.extend(
        entries: [
          (target: fixture.root, arguments: [fixture.unknown]),
        ],
      );
      final facts = flow.facts;
      expect(facts.activationsOf(fixture.opaque), isNotEmpty);
      expect(facts.activationsOf(fixture.helper).length, greaterThan(1));
      expect(facts.returnedBy(fixture.root).integers!.contains(144), isTrue);
    },
  );

  test('an identical recursive access plan does not prove termination', () {
    final fixture = _dispatch();
    final recurse = FunctionTarget(_uri, 'recurse', .integer, [
      .boolean,
      fixture.root.parameterTypes.single,
    ]);
    final head = Block(recurse.parameterTypes), again = Block(), done = Block();
    head.finish(Branch(head.parameters.first, Jump(again), Jump(done)));
    again.finish(Return(again.emit(DirectCall(recurse, head.parameters))));
    done.finish(
      Return(done.emit(DirectCall(fixture.helper, [head.parameters.last]))),
    );
    final root = FunctionTarget(_uri, 'recursiveRoot', .integer, [.boolean]);
    final entry = Block(root.parameterTypes);
    final call = entry.emit(
      DirectCall(recurse, [entry.parameters.single, fixture.known.constant!]),
    );
    entry.finish(Return(call));
    final facts = ProgramFlow(
      IrProgram(
        fixture.program.classes,
        [
          ...fixture.program.functions,
          IrFunction(recurse, [head, again, done]),
          IrFunction(root, [entry]),
        ],
        globals: fixture.program.globals,
        externals: fixture.program.externals,
      ),
      [
        (target: root, arguments: [FlowValue.unknown(.boolean)]),
      ],
    ).facts;
    expect(_number(facts.returnedBy(root)), 7);
    expect(facts.canDiscard(call), isFalse);
    expect(facts.activationsOf(fixture.opaque), isEmpty);
  });

  test('forwarded non-null inputs exclude an impossible callback branch', () {
    final leaf = FunctionTarget(_uri, 'leaf', .integer, [.object]);
    final body = Block(leaf.parameterTypes),
        missing = Block(),
        present = Block();
    final callback = FunctionTarget(_uri, 'callback', .voidType, []);
    body.finish(
      Branch(
        body.emit(Equals(body.parameters.single, const Constant.nullValue())),
        Jump(missing),
        Jump(present),
      ),
    );
    missing.emit(DirectCall(callback, []));
    missing.finish(const Return(Constant.integer(9)));
    present.finish(const Return(Constant.integer(7)));
    final forward = FunctionTarget(_uri, 'forward', .integer, [.object]);
    final forwarded = Block(forward.parameterTypes);
    forwarded.finish(
      Return(forwarded.emit(DirectCall(leaf, forwarded.parameters))),
    );
    final root = FunctionTarget(_uri, 'root', .integer, [.object]);
    final entry = Block(root.parameterTypes);
    final globals = [
      for (var i = 0; i < 16; i++)
        GlobalVariable(_uri, 'noise$i', ValueType.integer.nullable),
    ];
    Value sum = const Constant.integer(0);
    for (var i = 0; i < globals.length; i++) {
      entry.emit(StoreGlobal(globals[i], Constant.integer(i)));
      final result = entry.emit(DirectCall(forward, entry.parameters));
      sum = entry.emit(IntBinary(.add, sum, result));
    }
    entry.finish(Return(sum));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(root, [entry]),
          IrFunction(forward, [forwarded]),
          IrFunction(leaf, [body, missing, present]),
        ],
        globals: globals,
        externals: [IrExternal(callback)],
      ),
      [
        (target: root, arguments: [FlowValue.unknown(.object)]),
      ],
    ).facts;
    expect(_number(facts.returnedBy(root)), 112);
    expect(facts.activationsOf(forward), hasLength(1));
    expect(facts.activationsOf(leaf), hasLength(1));
    expect(facts.definitions, isNot(contains(callback)));
  });

  test(
    'selected virtual exceptions preserve writes and caller private state',
    () {
      final base = ClassType(_uri, 'Base', isAbstract: true);
      final actual = ClassType(_uri, 'Actual', superclass: base);
      final other = ClassType(_uri, 'Other', superclass: base);
      final declaration = _method(base, abstract: true);
      final selected = _method(actual), opaque = _method(other);
      final observed = GlobalVariable(_uri, 'observed', .integer, isLate: true);
      final private = GlobalVariable(_uri, 'private', .integer, isLate: true);
      final callback = FunctionTarget(_uri, 'callback', .voidType, []);
      final throwing = Block(selected.parameterTypes);
      throwing.emit(StoreGlobal(observed, const Constant.integer(9)));
      throwing.finish(Throw(const Constant.string('failure')));
      final unknown = Block(opaque.parameterTypes);
      unknown.emit(DirectCall(callback, []));
      unknown.finish(const Return(Constant.integer(3)));
      final helper = FunctionTarget(_uri, 'helper', .integer, [base]);
      final body = Block(helper.parameterTypes);
      body.finish(
        Return(
          body.emit(InstanceCall(declaration, body.parameters.single, [])),
        ),
      );
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block(), done = Block(), failed = Block();
      entry.emit(StoreGlobal(observed, const Constant.integer(1)));
      entry.emit(StoreGlobal(private, const Constant.integer(55)));
      final call = DirectCall(helper, [ObjectConstant(actual, {})]);
      entry.finish(Invoke(call, onReturn: Jump(done), onThrow: Jump(failed)));
      done.finish(const Return(Constant.integer(0)));
      failed.finish(
        Return(
          failed.emit(
            IntBinary(
              .add,
              failed.emit(LoadGlobal(observed)),
              failed.emit(LoadGlobal(private)),
            ),
          ),
        ),
      );
      final facts = ProgramFlow(
        IrProgram(
          [
            IrClass(base, [], members: [declaration]),
            IrClass(actual, [], members: [selected]),
            IrClass(other, [], members: [opaque]),
          ],
          [
            IrFunction(root, [entry, done, failed]),
            IrFunction(helper, [body]),
            IrFunction(selected, [throwing]),
            IrFunction(opaque, [unknown]),
          ],
          globals: [observed, private],
          externals: [IrExternal(callback)],
        ),
        [(target: root, arguments: <FlowValue>[])],
      ).facts;
      expect(_number(facts.returnedBy(root)), 64);
      expect(
        facts.failureOf(call).exception.constant,
        const Constant.string('failure'),
      );
      expect(facts.exitsOf(call), (normal: false, exceptional: true));
      expect(facts.activationsOf(opaque), isEmpty);
    },
  );
}

FunctionTarget _method(ClassType owner, {bool abstract = false}) =>
    FunctionTarget(
      _uri,
      'read',
      .integer,
      [],
      owner: owner,
      kind: .method,
      isAbstract: abstract,
    );

({
  IrProgram program,
  FunctionTarget root,
  FunctionTarget helper,
  FunctionTarget pure,
  FunctionTarget opaque,
  FlowValue known,
  FlowValue unknown,
})
_dispatch() {
  final base = ClassType(_uri, 'Base', isAbstract: true);
  final pure = ClassType(_uri, 'Pure', superclass: base);
  final opaque = ClassType(_uri, 'Opaque', superclass: base);
  final declaration = _method(base, abstract: true);
  final pureRead = _method(pure), opaqueRead = _method(opaque);
  final callback = FunctionTarget(_uri, 'callback', .voidType, []);
  final pureBody = Block(pureRead.parameterTypes)
    ..finish(const Return(Constant.integer(7)));
  final opaqueBody = Block(opaqueRead.parameterTypes);
  opaqueBody.emit(DirectCall(callback, []));
  opaqueBody.finish(const Return(Constant.integer(9)));
  final helper = FunctionTarget(_uri, 'helper', .integer, [base]);
  final helperBody = Block(helper.parameterTypes);
  helperBody.finish(
    Return(
      helperBody.emit(
        InstanceCall(declaration, helperBody.parameters.single, []),
      ),
    ),
  );
  final globals = [
    for (var i = 0; i < 16; i++)
      GlobalVariable(_uri, 'noise$i', ValueType.integer.nullable),
  ];
  final root = FunctionTarget(_uri, 'root', .integer, [base]);
  final entry = Block(root.parameterTypes);
  Value sum = const Constant.integer(0);
  for (var i = 0; i < globals.length; i++) {
    entry.emit(StoreGlobal(globals[i], Constant.integer(i)));
    final call = entry.emit(DirectCall(helper, entry.parameters));
    sum = entry.emit(IntBinary(.add, sum, call));
  }
  entry.finish(Return(sum));
  return (
    program: IrProgram(
      [
        IrClass(base, [], members: [declaration]),
        IrClass(pure, [], members: [pureRead]),
        IrClass(opaque, [], members: [opaqueRead]),
      ],
      [
        IrFunction(root, [entry]),
        IrFunction(helper, [helperBody]),
        IrFunction(pureRead, [pureBody]),
        IrFunction(opaqueRead, [opaqueBody]),
      ],
      globals: globals,
      externals: [IrExternal(callback)],
    ),
    root: root,
    helper: helper,
    pure: pureRead,
    opaque: opaqueRead,
    known: FlowValue.constant(ObjectConstant(pure, {})),
    unknown: FlowValue.unknown(base),
  );
}

Object? _number(FlowValue value) => switch (value.constant) {
  ScalarConstant(:final value) => value,
  _ => null,
};

final _adversarialUri = Uri.parse('memory:independent-access');

void _inputAccessDependencies() {
  for (final recursive in [false, true]) {
    test(
      '${recursive ? 'recursive argument' : 'cyclic phi'} changes must restore later writes',
      () {
        final observed = GlobalVariable(
          _adversarialUri,
          'observed',
          .integer,
          isLate: true,
        );
        final private = GlobalVariable(
          _adversarialUri,
          'private',
          .integer,
          isLate: true,
        );
        final callback = FunctionTarget(
          _adversarialUri,
          'opaque',
          .voidType,
          [],
        );
        final helper = FunctionTarget(_adversarialUri, 'helper', .voidType, [
          .boolean,
          .boolean,
        ]);
        final head = Block(helper.parameterTypes),
            opaque = Block(),
            start = Block(),
            loop = Block([.boolean]),
            again = Block(),
            done = Block();
        head.finish(Branch(head.parameters[0], Jump(opaque), Jump(start)));
        opaque.emit(DirectCall(callback, []));
        opaque.finish(const Return());
        if (recursive) {
          start.finish(Branch(head.parameters[1], Jump(again), Jump(done)));
          again.emit(
            DirectCall(helper, [
              head.parameters[0],
              const Constant.boolean(false),
            ]),
          );
          again.finish(const Return());
        } else {
          start.finish(Jump(loop, [head.parameters[1]]));
          loop.finish(Branch(loop.parameters.single, Jump(again), Jump(done)));
          again.finish(Jump(loop, [const Constant.boolean(false)]));
        }
        done.emit(StoreGlobal(observed, const Constant.integer(9)));
        done.finish(const Return());
        final root = FunctionTarget(_adversarialUri, 'root', .integer, []);
        final entry = Block();
        entry.emit(StoreGlobal(observed, const Constant.integer(1)));
        entry.emit(StoreGlobal(private, const Constant.integer(55)));
        entry.emit(
          DirectCall(helper, [
            const Constant.boolean(false),
            const Constant.boolean(true),
          ]),
        );
        entry.finish(
          Return(
            entry.emit(
              IntBinary(
                .add,
                entry.emit(LoadGlobal(observed)),
                entry.emit(LoadGlobal(private)),
              ),
            ),
          ),
        );
        final rootBody = IrFunction(root, [entry]);
        final program = IrProgram(
          [],
          [
            rootBody,
            IrFunction(helper, [
              head,
              opaque,
              start,
              if (!recursive) loop,
              again,
              done,
            ]),
          ],
          globals: [observed, private],
          externals: [IrExternal(callback)],
        );
        expect(IrInterpreter(program, {}).run(rootBody, []), 64);
        final facts = ProgramFlow(program, [
          (target: root, arguments: <FlowValue>[]),
        ]).facts;
        expect(_number(facts.returnedBy(root)), 64);
        expect(facts.definitions, isNot(contains(callback)));
      },
    );
  }

  test('mayThrow includes both continuations after actual branch pruning', () {
    final observed = GlobalVariable(
      _adversarialUri,
      'observed',
      .integer,
      isLate: true,
    );
    final private = GlobalVariable(
      _adversarialUri,
      'private',
      .integer,
      isLate: true,
    );
    final opaqueTarget = FunctionTarget(
      _adversarialUri,
      'opaque',
      .voidType,
      [],
    );
    final leaf = FunctionTarget(_adversarialUri, 'mayThrow', .voidType, []);
    final helper = FunctionTarget(_adversarialUri, 'helper', .voidType, [
      .boolean,
    ]);
    final head = Block(helper.parameterTypes),
        opaque = Block(),
        body = Block(),
        normal = Block(),
        caught = Block();
    head.finish(Branch(head.parameters.single, Jump(opaque), Jump(body)));
    opaque.emit(DirectCall(opaqueTarget, []));
    opaque.finish(const Return());
    final invocation = DirectCall(leaf, []);
    body.finish(
      Invoke(invocation, onReturn: Jump(normal), onThrow: Jump(caught)),
    );
    normal.emit(StoreGlobal(observed, const Constant.integer(2)));
    normal.finish(const Return());
    caught.emit(StoreGlobal(observed, const Constant.integer(9)));
    caught.finish(const Return());
    final root = FunctionTarget(_adversarialUri, 'root', .integer, []);
    final entry = Block();
    entry.emit(StoreGlobal(observed, const Constant.integer(1)));
    entry.emit(StoreGlobal(private, const Constant.integer(55)));
    entry.emit(DirectCall(helper, [const Constant.boolean(false)]));
    entry.finish(
      Return(
        entry.emit(
          IntBinary(
            .add,
            entry.emit(LoadGlobal(observed)),
            entry.emit(LoadGlobal(private)),
          ),
        ),
      ),
    );
    final rootBody = IrFunction(root, [entry]);
    final program = IrProgram(
      [],
      [
        rootBody,
        IrFunction(helper, [head, opaque, body, normal, caught]),
      ],
      globals: [observed, private],
      externals: [
        IrExternal(opaqueTarget),
        IrExternal(
          leaf,
          effects: {Effect.mayThrow},
          memory: const ExternalMemory.unchanged(),
          capturesArguments: false,
          terminates: true,
        ),
      ],
    );
    for (final throws in [false, true]) {
      expect(
        IrInterpreter(
          program,
          {},
          externalCalls: {
            leaf: (_) {
              if (throws) throw StateError('selected exception');
              return null;
            },
          },
        ).run(rootBody, []),
        throws ? 64 : 57,
      );
    }
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ]).facts;
    final value = facts.returnedBy(root);
    expect(value.integers!.contains(57), isTrue);
    expect(value.integers!.contains(64), isTrue);
    expect(facts.exitsOf(invocation), (normal: true, exceptional: true));
    expect(facts.definitions, isNot(contains(opaqueTarget)));
  });

  test('mutable field branches remain input-state dependencies', () {
    final owner = ClassType(_adversarialUri, 'Box');
    final flag = InstanceField(owner, 'flag', .boolean);
    final observed = GlobalVariable(
      _adversarialUri,
      'observed',
      .integer,
      isLate: true,
    );
    final opaqueTarget = FunctionTarget(
      _adversarialUri,
      'opaque',
      .voidType,
      [],
    );
    final helper = FunctionTarget(_adversarialUri, 'helper', .integer, [
      .boolean,
      owner,
    ]);
    final head = Block(helper.parameterTypes),
        opaque = Block(),
        read = Block(),
        yes = Block(),
        no = Block();
    head.finish(Branch(head.parameters[0], Jump(opaque), Jump(read)));
    opaque.emit(DirectCall(opaqueTarget, []));
    opaque.finish(const Return(Constant.integer(-1)));
    read.finish(
      Branch(
        read.emit(LoadField(flag, head.parameters[1])),
        Jump(yes),
        Jump(no),
      ),
    );
    yes.finish(Return(yes.emit(LoadGlobal(observed))));
    no.finish(const Return(Constant.integer(5)));
    final root = FunctionTarget(_adversarialUri, 'root', .integer, []);
    final entry = Block();
    final box = entry.emit(NewPayload(owner, const Constant.integer(0)));
    entry.emit(StoreGlobal(observed, const Constant.integer(9)));
    entry.emit(StoreField(flag, box, const Constant.boolean(false)));
    final first = entry.emit(
      DirectCall(helper, [const Constant.boolean(false), box]),
    );
    entry.emit(StoreField(flag, box, const Constant.boolean(true)));
    final second = entry.emit(
      DirectCall(helper, [const Constant.boolean(false), box]),
    );
    entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
    final rootBody = IrFunction(root, [entry]);
    final program = IrProgram(
      [
        IrClass(owner, [flag]),
      ],
      [
        rootBody,
        IrFunction(helper, [head, opaque, read, yes, no]),
      ],
      globals: [observed],
      externals: [IrExternal(opaqueTarget)],
    );
    expect(IrInterpreter(program, {}).run(rootBody, []), 14);
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ]).facts;
    expect(_number(facts.returnedBy(root)), 14);
    expect(facts.activationsOf(helper), hasLength(2));
  });

  test('known closure target retains hidden captured mutable state', () {
    final root = FunctionTarget(_adversarialUri, 'root', .integer, []);
    final cellType = CellType(.integer);
    final closureTarget = FunctionTarget(
      _adversarialUri,
      'closure',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 1,
      captures: [cellType],
    );
    final closureBody = Block(closureTarget.parameterTypes);
    closureBody.finish(
      Return(closureBody.emit(ReadCell(closureBody.parameters[1]))),
    );
    final opaqueTarget = FunctionTarget(
      _adversarialUri,
      'opaque',
      .voidType,
      [],
    );
    final helper = FunctionTarget(_adversarialUri, 'helper', .integer, [
      .boolean,
      closureTarget.signature,
    ]);
    final head = Block(helper.parameterTypes), opaque = Block(), call = Block();
    head.finish(Branch(head.parameters[0], Jump(opaque), Jump(call)));
    opaque.emit(DirectCall(opaqueTarget, []));
    opaque.finish(const Return(Constant.integer(-1)));
    call.finish(
      Return(
        call.emit(FunctionCall(head.parameters[1], [], {}, [], closureTarget)),
      ),
    );
    final entry = Block();
    final cell = entry.emit(NewCell(cellType, const Constant.integer(2)));
    final closure = entry.emit(MakeClosure(closureTarget, [cell]));
    final first = entry.emit(
      DirectCall(helper, [const Constant.boolean(false), closure]),
    );
    entry.emit(WriteCell(cell, const Constant.integer(9)));
    final second = entry.emit(
      DirectCall(helper, [const Constant.boolean(false), closure]),
    );
    entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
    final rootBody = IrFunction(root, [entry]);
    final program = IrProgram(
      [],
      [
        rootBody,
        IrFunction(helper, [head, opaque, call]),
        IrFunction(closureTarget, [closureBody]),
      ],
      externals: [IrExternal(opaqueTarget)],
    );
    expect(IrInterpreter(program, {}).run(rootBody, []), 11);
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ]).facts;
    expect(_number(facts.returnedBy(root)), 11);
    expect(facts.activationsOf(helper), hasLength(2));
  });
}
