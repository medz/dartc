import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:native-access');
final _bytes = ClassType(_uri, 'Bytes');
final _i64 = NativeScalarType(Int64);
final _layout = _Layout();

void main() {
  test(
    'release through a Dart call follows each previously built list node',
    () {
      final uri = Uri.parse('memory:ordinary-node-release');
      final node = ClassType(uri, 'Node');
      final address = InstanceField(node, 'address', .integer);
      final next = InstanceField(node, 'next', node.nullable);
      final map = FunctionTarget(uri, 'map', .integer, [.integer]);
      final unmap = FunctionTarget(uri, 'unmap', .voidType, [
        .integer,
        .integer,
      ]);
      final make = FunctionTarget(uri, 'prepend', node, [node.nullable]);
      final drop = FunctionTarget(uri, 'releaseNode', .voidType, [node]);
      final root = FunctionTarget(uri, 'choose', .integer, []);
      final flag = GlobalVariable(uri, 'flag', .integer, isLate: true);
      const length = Constant.integer(4096), zero = Constant.integer(0);
      final create = Block(make.parameterTypes),
          valid = Block(),
          failed = Block();
      final base = create.emit(DirectCall(map, [length]));
      create.finish(
        Branch(create.emit(Equals(base, zero)), Jump(failed), Jump(valid)),
      );
      failed.finish(Throw(const Constant.string('map failed')));
      final allocation = valid.emit(NewPayload(node, zero));
      valid.emit(StoreField(address, allocation, base));
      valid.emit(StoreField(next, allocation, create.parameters.single));
      valid.finish(Return(allocation));
      final dispose = Block(drop.parameterTypes);
      dispose.emit(
        DirectCall(unmap, [
          dispose.emit(LoadField(address, dispose.parameters.single)),
          length,
        ]),
      );
      dispose.finish(const Return());
      final build = Block(),
          header = Block([node.nullable]),
          body = Block([node]),
          done = Block();
      Value head = const Constant.nullValue();
      for (var i = 0; i < 4; i++) {
        head = build.emit(DirectCall(make, [head]));
      }
      build.emit(StoreGlobal(flag, const Constant.integer(42)));
      build.finish(Jump(header, [head]));
      final present = header.emit(
        TypeTest(header.parameters.single, .nullType, negated: true),
      );
      header.finish(
        Branch(present, Jump(body, [present.refinement(true)!]), Jump(done)),
      );
      final following = body.emit(LoadField(next, body.parameters.single));
      body.emit(DirectCall(drop, [body.parameters.single]));
      body.finish(Jump(header, [following]));
      done.finish(Return(done.emit(LoadGlobal(flag))));
      final ir = IrProgram(
        [
          IrClass(node, [address, next]),
        ],
        [
          IrFunction(root, [build, header, body, done]),
          IrFunction(make, [create, valid, failed]),
          IrFunction(drop, [dispose]),
        ],
        globals: [flag],
        externals: [
          IrExternal(
            map,
            effects: const {.writesStorage},
            memory: const .zeroed(0),
          ),
          IrExternal(
            unmap,
            effects: const {.writesStorage},
            memory: const .release(0, 1),
            capturesArguments: false,
          ),
        ],
      );
      final facts = ProgramFlow(ir, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(facts.returnedBy(root).constant, const Constant.integer(42));
    },
  );

  test('native address list preserves each live control page', () {
    final uri = Uri.parse('memory:control-list');
    final map = FunctionTarget(uri, 'map', .integer, [.integer]);
    final unmap = FunctionTarget(uri, 'unmap', .voidType, [.integer, .integer]);
    final global = GlobalVariable(uri, 'marker', .integer, isLate: true);
    final root = FunctionTarget(uri, 'root', .integer, []);
    final entry = Block(),
        failed = Block(),
        header = Block([ValueType.integer]);
    final body = Block(), done = Block();
    const zero = Constant.integer(0), word = Constant.integer(8);
    final allocations = <Block>[entry];
    Value head = zero;
    for (final bytes in [16, 32, 48, 64]) {
      final current = allocations.last, next = Block();
      final length = Constant.integer(bytes);
      final address = current.emit(DirectCall(map, [length]));
      current.finish(
        Branch(current.emit(Equals(address, zero)), Jump(failed), Jump(next)),
      );
      next.emit(StoreNative(address, _i64, head));
      next.emit(
        StoreNative(next.emit(IntBinary(.add, address, word)), _i64, length),
      );
      head = address;
      allocations.add(next);
    }
    failed.finish(Throw(const Constant.string('map failed')));
    allocations.last.emit(StoreGlobal(global, const Constant.integer(42)));
    allocations.last.finish(Jump(header, [head]));
    final cur = header.parameters.single;
    header.finish(
      Branch(header.emit(Equals(cur, zero)), Jump(done), Jump(body)),
    );
    final next = body.emit(LoadNative(cur, _i64));
    final size = body.emit(
      LoadNative(body.emit(IntBinary(.add, cur, word)), _i64),
    );
    body.emit(DirectCall(unmap, [cur, size]));
    body.finish(Jump(header, [next]));
    done.finish(Return(done.emit(LoadGlobal(global))));
    final graph = IrProgram(
      [],
      [
        IrFunction(root, [...allocations, failed, header, body, done]),
      ],
      globals: [global],
      externals: [
        IrExternal(
          map,
          effects: const {.writesStorage},
          memory: const .zeroed(0),
        ),
        IrExternal(
          unmap,
          effects: const {.writesStorage},
          memory: const .release(0, 1),
          capturesArguments: false,
        ),
      ],
    );
    final facts = ProgramFlow(graph, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(facts.returnedBy(root).constant, const Constant.integer(42));
  });

  test('a joined stack address stays paired with its incoming storage', () {
    final target = FunctionTarget(_uri, 'write', .integer, [.boolean]);
    final flag = GlobalVariable(_uri, 'flag', .integer, isLate: true);
    final entry = Block(target.parameterTypes);
    final fast = Block();
    // Let the direct edge reach the store before the other allocation arrives.
    final delayed = List.generate(7, (_) => Block());
    final join = Block([ValueType.integer]);
    final use = Block();
    entry.emit(StoreGlobal(flag, const Constant.integer(42)));
    entry.finish(
      Branch(entry.parameters.single, Jump(fast), Jump(delayed.first)),
    );
    final first = fast.emit(NativeLocalStorage(_i64));
    fast.finish(Jump(join, [first]));
    for (var i = 1; i < delayed.length; i++) {
      delayed[i - 1].finish(Jump(delayed[i]));
    }
    final second = delayed.last.emit(NativeLocalStorage(_i64));
    delayed.last.finish(Jump(join, [second]));
    join.finish(Jump(use));
    use.emit(
      StoreNative(join.parameters.single, _i64, const Constant.integer(7)),
    );
    use.finish(Return(use.emit(LoadGlobal(flag))));
    final fn = IrFunction(target, [entry, fast, ...delayed, join, use]);
    final ir = IrProgram([], [fn], globals: [flag]);
    final facts = ProgramFlow(ir, [
      (target: target, arguments: [FlowValue.unknown(ValueType.boolean)]),
    ], memoryLayout: _layout).facts;
    expect(facts.returnedBy(target).constant, const Constant.integer(42));
  });

  for (final unwind in [false, true]) {
    test(
      unwind
          ? 'a caught mapping retains its published header'
          : 'only a published mapping has a readable initialized header',
      () {
        final map = FunctionTarget(_uri, 'map', .integer, [.integer]);
        final make = FunctionTarget(
          _uri,
          'make',
          unwind ? .never : .integer,
          [],
        );
        final root = FunctionTarget(_uri, 'entry', .integer, []);
        const zero = Constant.integer(0);
        const size = Constant.integer(65536);
        final entry = Block(), exhausted = Block(), initialized = Block();
        final page = entry.emit(DirectCall(map, [size]));
        entry.finish(
          Branch(
            entry.emit(Equals(page, zero)),
            Jump(exhausted),
            Jump(initialized),
          ),
        );
        exhausted.finish(unwind ? Throw(zero) : Return(zero));
        final slot = initialized.emit(
          IntBinary(.add, page, const Constant.integer(8)),
        );
        initialized.emit(StoreNative(slot, _i64, size));
        initialized.finish(unwind ? Throw(page) : Return(page));
        final invoke = Block(), absent = Block(), present = Block();
        final caught = Block([ValueType.object]);
        final call = DirectCall(make, []);
        final Value actual;
        final Block check;
        if (unwind) {
          invoke.finish(
            Invoke(
              call,
              onReturn: null,
              onThrow: Jump(caught, [UnwindValue.exception]),
            ),
          );
          check = caught;
          actual = caught.emit(
            UncheckedCast(caught.parameters.single, .integer),
          );
        } else {
          check = invoke;
          actual = invoke.emit(call);
        }
        check.finish(
          Branch(check.emit(Equals(actual, zero)), Jump(absent), Jump(present)),
        );
        absent.finish(Return(zero));
        final read = present.emit(
          LoadNative(
            present.emit(IntBinary(.add, actual, const Constant.integer(8))),
            _i64,
          ),
        );
        present.finish(Return(read));
        final graph = IrProgram(
          [],
          [
            IrFunction(make, [entry, exhausted, initialized]),
            IrFunction(root, [invoke, if (unwind) caught, absent, present]),
          ],
          externals: [
            IrExternal(
              map,
              effects: const {Effect.writesStorage},
              memory: const ExternalMemory.zeroed(0),
            ),
          ],
        );
        final facts = ProgramFlow(graph, [
          (target: root, arguments: <FlowValue>[]),
        ], memoryLayout: _layout).facts;
        expect(facts.valueOf(read).constant, size);
      },
    );
  }

  test('one throw site preserves both incoming mapping lifetimes', () {
    final uri = Uri.parse('memory:same-exit');
    const eight = Constant.integer(8), zero = Constant.integer(0);
    final head = GlobalVariable(uri, 'head', .integer, isLate: true);
    final marker = GlobalVariable(uri, 'marker', .integer, isLate: true);
    final reserve = FunctionTarget(uri, 'reserve', .integer, [.integer]);
    final release = FunctionTarget(uri, 'release', .voidType, [
      .integer,
      .integer,
    ]);
    final fail = FunctionTarget(uri, 'fail', .never, [.integer, .boolean]);
    final choice = Block(fail.parameterTypes), closed = Block(), open = Block();
    choice.finish(Branch(choice.parameters.last, Jump(closed), Jump(open)));
    closed.emit(DirectCall(release, [choice.parameters.first, eight]));
    closed.finish(Throw(const Constant.string('closed')));
    open.finish(Throw(const Constant.string('open')));

    final attempt = FunctionTarget(uri, 'attempt', .never, [
      .integer,
      .integer,
      .boolean,
      .boolean,
    ]);
    final setup = Block(attempt.parameterTypes),
        retire = Block(),
        live = Block();
    setup.finish(Branch(setup.parameters[2], Jump(retire), Jump(live)));
    retire.emit(StoreGlobal(head, zero));
    retire.emit(DirectCall(release, [setup.parameters.first, eight]));
    live.emit(StoreGlobal(head, setup.parameters.first));
    for (final path in [retire, live]) {
      final terminal = path.emit(
        DirectCall(fail, [setup.parameters[1], setup.parameters.last]),
      );
      path.finish(Unreachable(terminal));
    }

    final dispose = FunctionTarget(uri, 'dispose', .voidType, []);
    final inspect = Block(), drop = Block(), done = Block();
    final address = inspect.emit(LoadGlobal(head));
    inspect.finish(
      Branch(inspect.emit(Equals(address, zero)), Jump(done), Jump(drop)),
    );
    drop.emit(DirectCall(release, [address, eight]));
    drop.finish(Jump(done));
    done.finish(const Return());

    final root = FunctionTarget(uri, 'root', .integer, [.boolean, .boolean]);
    final start = Block(root.parameterTypes),
        second = Block(),
        go = Block(),
        bad = Block(),
        caught = Block();
    final page = start.emit(DirectCall(reserve, [eight]));
    start.finish(
      Branch(start.emit(Equals(page, zero)), Jump(bad), Jump(second)),
    );
    final scratch = second.emit(DirectCall(reserve, [eight]));
    second.finish(
      Branch(second.emit(Equals(scratch, zero)), Jump(bad), Jump(go)),
    );
    bad.finish(Throw(const Constant.string('no storage')));
    go.emit(StoreGlobal(marker, const Constant.integer(42)));
    go.finish(
      Invoke(
        DirectCall(attempt, [page, scratch, ...start.parameters]),
        onReturn: null,
        onThrow: Jump(caught),
      ),
    );
    caught.emit(DirectCall(dispose, []));
    caught.finish(Return(caught.emit(LoadGlobal(marker))));
    final ir = IrProgram(
      [],
      [
        IrFunction(root, [start, second, go, bad, caught]),
        IrFunction(attempt, [setup, retire, live]),
        IrFunction(fail, [choice, closed, open]),
        IrFunction(dispose, [inspect, drop, done]),
      ],
      globals: [head, marker],
      externals: [
        IrExternal(
          reserve,
          effects: const {.writesStorage},
          memory: const .zeroed(0),
        ),
        IrExternal(
          release,
          effects: const {.writesStorage},
          memory: const .release(0, 1),
          capturesArguments: false,
        ),
      ],
    );
    final facts = ProgramFlow(ir, [
      (
        target: root,
        arguments: [FlowValue.unknown(.boolean), FlowValue.unknown(.boolean)],
      ),
    ], memoryLayout: _layout).facts;
    expect(facts.returnedBy(root).constant, const Constant.integer(42));
  });

  for (final hasSecond in [false, true]) {
    test('cleanup visits each known non-null node (second=$hasSecond)', () {
      final uri = Uri.parse('memory:nullable-cleanup');
      final map = FunctionTarget(uri, 'map', .integer, [.integer]);
      final unmap = FunctionTarget(uri, 'unmap', .voidType, [
        .integer,
        .integer,
      ]);
      final global = GlobalVariable(uri, 'flag', .integer, isLate: true);
      final target = FunctionTarget(uri, 'dispose', .integer, []);
      final entry = Block(target.parameterTypes);
      final start = Block([ValueType.integer]);
      final loop = Block([ValueType.string.nullable]);
      final body = Block(), exit = Block(), failed = Block();
      final base = entry.emit(DirectCall(map, [const Constant.integer(8)]));
      final missing = entry.emit(Equals(base, const Constant.integer(0)));
      entry.finish(Branch(missing, Jump(failed), Jump(start, [base])));
      failed.finish(Throw(const Constant.string('map failed')));
      start.emit(StoreGlobal(global, const Constant.integer(42)));
      start.finish(Jump(loop, [const Constant.string('first')]));
      final hasNext = loop.emit(
        TypeTest(loop.parameters.single, .nullType, negated: true),
      );
      loop.finish(Branch(hasNext, Jump(body), Jump(exit)));
      final release = Block(), last = Block();
      const first = Constant.string('first');
      if (hasSecond) {
        final atFirst = body.emit(Equals(loop.parameters.single, first));
        body.finish(Branch(atFirst, Jump(release), Jump(last)));
        last.emit(StoreGlobal(global, const Constant.integer(73)));
        last.finish(Return(last.emit(LoadGlobal(global))));
      } else {
        body.finish(Jump(release));
      }
      release.emit(
        DirectCall(unmap, [start.parameters.single, const Constant.integer(8)]),
      );
      release.finish(
        Jump(loop, [
          hasSecond
              ? const Constant.string('last')
              : const Constant.nullValue(),
        ]),
      );
      exit.finish(Return(exit.emit(LoadGlobal(global))));
      final program = IrProgram(
        [],
        [
          IrFunction(target, [
            entry,
            start,
            loop,
            body,
            release,
            if (hasSecond) last,
            exit,
            failed,
          ]),
        ],
        globals: [global],
        externals: [
          IrExternal(
            map,
            effects: const {.writesStorage},
            memory: const .zeroed(0),
          ),
          IrExternal(
            unmap,
            effects: const {.writesStorage},
            memory: const .release(0, 1),
            capturesArguments: false,
          ),
        ],
      );
      final flow = ProgramFlow(program, [
        (target: target, arguments: []),
      ], memoryLayout: _layout).facts;
      expect(
        flow.returnedBy(target).constant,
        hasSecond ? const Constant.integer(73) : const Constant.integer(42),
      );
    });
  }

  test(
    'distinct throws retain the lifetime required by exceptional cleanup',
    () {
      final uri = Uri.parse('memory:exit-lifetimes');
      final flag = GlobalVariable(uri, 'flag', .integer, isLate: true);
      final head = GlobalVariable(uri, 'head', .integer, isLate: true);
      final map = FunctionTarget(uri, 'map', .integer, [.integer]);
      final unmap = FunctionTarget(uri, 'unmap', .voidType, [
        .integer,
        .integer,
      ]);
      const size = Constant.integer(8), zero = Constant.integer(0);
      final root = FunctionTarget(uri, 'root', .integer, [.boolean, .boolean]);
      final throws = FunctionTarget(uri, 'throwWhileSettingUp', .never, [
        .integer,
        .boolean,
        .boolean,
      ]);
      final cleanup = FunctionTarget(uri, 'cleanup', .voidType, []);
      final choose = Block(throws.parameterTypes),
          retire = Block(),
          live = Block();
      final initiallyLive = Block(), written = Block();
      choose.finish(Branch(choose.parameters[1], Jump(retire), Jump(live)));
      retire.emit(StoreGlobal(head, zero));
      retire.emit(DirectCall(unmap, [choose.parameters.first, size]));
      retire.finish(Throw(const Constant.string('retired')));
      live.emit(StoreGlobal(head, choose.parameters.first));
      live.finish(
        Branch(choose.parameters[2], Jump(initiallyLive), Jump(written)),
      );
      initiallyLive.finish(Throw(const Constant.string('live')));
      written.emit(
        StoreNative(
          choose.parameters.first,
          NativeScalarType(Int64),
          const Constant.integer(12),
        ),
      );
      written.finish(Throw(const Constant.string('written')));

      final close = Block(), release = Block(), finish = Block();
      final page = close.emit(LoadGlobal(head));
      close.finish(
        Branch(close.emit(Equals(page, zero)), Jump(finish), Jump(release)),
      );
      release.emit(DirectCall(unmap, [page, size]));
      release.finish(Jump(finish));
      finish.finish(const Return());

      final entry = Block(root.parameterTypes),
          ready = Block([ValueType.integer]),
          bad = Block(),
          caught = Block();
      final raw = entry.emit(DirectCall(map, [size]));
      entry.finish(
        Branch(entry.emit(Equals(raw, zero)), Jump(bad), Jump(ready, [raw])),
      );
      bad.finish(Throw(const Constant.string('map failed')));
      ready.emit(StoreGlobal(flag, const Constant.integer(42)));
      ready.finish(
        Invoke(
          DirectCall(throws, [ready.parameters.first, ...entry.parameters]),
          onReturn: null,
          onThrow: Jump(caught),
        ),
      );
      caught.emit(DirectCall(cleanup, []));
      caught.finish(Return(caught.emit(LoadGlobal(flag))));
      final ir = IrProgram(
        [],
        [
          IrFunction(root, [entry, ready, bad, caught]),
          IrFunction(throws, [choose, retire, live, initiallyLive, written]),
          IrFunction(cleanup, [close, release, finish]),
        ],
        globals: [flag, head],
        externals: [
          IrExternal(
            map,
            effects: const {.writesStorage},
            memory: const .zeroed(0),
          ),
          IrExternal(
            unmap,
            effects: const {.writesStorage},
            memory: const .release(0, 1),
            capturesArguments: false,
          ),
        ],
      );
      final facts = ProgramFlow(ir, [
        (
          target: root,
          arguments: [FlowValue.unknown(.boolean), FlowValue.unknown(.boolean)],
        ),
      ], memoryLayout: _layout).facts;
      expect(facts.reachesBlock(release), isTrue);
      expect(facts.returnedBy(root).constant, const Constant.integer(42));
    },
  );

  test('a reference recovered inside a page retains its actual address', () {
    final map = FunctionTarget(_uri, 'map', .integer, [.integer]);
    final addressOf = FunctionTarget(_uri, 'addressOf', .integer, [.object]);
    final get = Block([.object]);
    get.finish(Return(get.emit(ReferenceAddress(get.parameters.single))));
    final root = FunctionTarget(_uri, 'slotAddress', .integer, [.integer]);
    final entry = Block([.integer]), success = Block(), failure = Block();
    final page = entry.emit(DirectCall(map, [const Constant.integer(4096)]));
    entry.finish(Branch(
      entry.emit(Equals(page, const Constant.integer(0))),
      Jump(failure),
      Jump(success),
    ));
    failure.finish(Throw(const Constant.string('map failed')));
    final offset = success.emit(IntBinary(
      .multiply, entry.parameters.single, const Constant.integer(64),
    ));
    final slot = success.emit(IntBinary(.add, page, offset));
    final object = success.emit(ReferenceFromAddress(slot, .object));
    success.finish(Return(success.emit(DirectCall(addressOf, [object]))));
    final program = IrProgram([], [
      IrFunction(root,[entry, success, failure]), IrFunction(addressOf,[get]),
    ], externals:[IrExternal(map, effects: const {}, capturesArguments: false,
        memory: const ExternalMemory.zeroed(0))]);
    final facts = ProgramFlow(program, [
      (target: root, arguments: [FlowValue.integerRange(FlowIntegerRange(0, 63))]),
    ], memoryLayout: _layout).facts;
    final result = facts.returnedBy(root);
    expect(result.unknownTypes, isEmpty);
    final address = result.addresses.single;
    expect(address.base, facts.valueOf(slot).addresses.single.base);
    expect(address.offsets, facts.valueOf(slot).addresses.single.offsets);
    expect(address.offsets, FlowIntegerRange(0, 4032, strideBits: 6));
  });

  test('an initialized object at a native region base can have any class', () {
    final allocate = FunctionTarget(_uri, 'reserve', .integer, [.integer]);
    final initialize = FunctionTarget(_uri, 'initializeObject', .voidType, [
      .integer,
      .integer,
    ]);
    final classify = FunctionTarget(_uri, 'classify', .boolean, []);
    final entry = Block(), success = Block(), failure = Block();
    const bytes = Constant.integer(48);
    final address = entry.emit(DirectCall(allocate, [bytes]));
    entry.finish(
      Branch(
        entry.emit(Equals(address, const Constant.integer(0))),
        Jump(failure),
        Jump(success),
      ),
    );
    failure.finish(const Return(Constant.boolean(false)));
    success.emit(DirectCall(initialize, [address, bytes]));
    final object = success.emit(ReferenceFromAddress(address, .object));
    final isInteger = success.emit(TypeTest(object, .integer));
    final boxed = Block(), ordinary = Block();
    success.finish(Branch(isInteger, Jump(boxed), Jump(ordinary)));
    boxed.finish(const Return(Constant.boolean(true)));
    ordinary.finish(const Return(Constant.boolean(false)));
    final program = IrProgram(
      [],
      [
        IrFunction(classify, [entry, success, failure, boxed, ordinary]),
      ],
      externals: [
        IrExternal(
          allocate,
          effects: {},
          capturesArguments: false,
          memory: const ExternalMemory.zeroed(0),
        ),
        IrExternal(
          initialize,
          effects: {Effect.writesStorage},
          capturesArguments: false,
          memory: const ExternalMemory.write(0, 1),
        ),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: classify, arguments: []),
    ], memoryLayout: _layout).facts;
    expect(
      [facts.reachesBlock(boxed), facts.reachesBlock(ordinary)],
      [true, true],
    );
  });

  test(
    'known ranges compose through reordered arguments and address arithmetic',
    () {
      final fixture = _program(indirect: true);
      final facts = _analyze(fixture);
      expect(_number(facts.returnedBy(fixture.root)), 66);
      expect(facts.activationsOf(fixture.store), hasLength(1));
      expect(facts.activationsOf(fixture.outer!), hasLength(1));
      expect(facts.activationsOf(fixture.inner!), hasLength(1));
    },
  );

  test('an inherited native context retains its anchored write capability', () {
    final fixture = _program(context: true);
    final facts = _analyze(fixture);
    expect(_number(facts.returnedBy(fixture.root)), 66);
    expect(facts.activationsOf(fixture.store), hasLength(1));
  });

  for (final kind in ['unknown', 'outside', 'loaded']) {
    test(
      '$kind addresses without a complete range proof retain full state',
      () {
        final fixture = _program(kind: kind);
        final facts = _analyze(fixture);
        expect(facts.activationsOf(fixture.store).length, greaterThan(1));
        final returned = facts.returnedBy(fixture.root);
        expect(returned.isBottom, isFalse);
        if (kind == 'loaded') {
          expect(_number(returned), 66);
        } else {
          expect(returned.constant, isNull);
        }
      },
    );
  }

  for (final release in [false, true]) {
    test(
      'external ${release ? 'release' : 'range write'} preserves its memory contract',
      () {
        final fixture = _program(
          kind: release ? 'external_release' : 'external_write',
        );
        final facts = _analyze(fixture);
        if (release) {
          expect(facts.returnedBy(fixture.root).constant, isNull);
          expect(facts.activationsOf(fixture.store).length, greaterThan(1));
        } else {
          expect(_number(facts.returnedBy(fixture.root)), 66);
          final root =
              fixture.program.implementationOf(fixture.root) as IrFunction;
          final calls = root.blocks
              .expand((block) => block.instructions)
              .whereType<DirectCall>()
              .where((call) => call.target == fixture.store)
              .toList();
          // The first external write replaces initial zero-byte facts. Further
          // unrelated cells must not introduce another memory input context.
          final stable = facts.callActivationsOf(calls[1]);
          expect(stable, hasLength(1));
          for (final call in calls.skip(2)) {
            expect(facts.callActivationsOf(call), stable);
          }
        }
      },
    );
  }
}

ProgramFlowFacts _analyze(_Fixture fixture) => ProgramFlow(fixture.program, [
  (
    target: fixture.root,
    arguments: fixture.root.parameterTypes.map(FlowValue.unknown).toList(),
  ),
], memoryLayout: _layout).facts;

final class _Fixture(
  final IrProgram program,
  final FunctionTarget root,
  final FunctionTarget store,
  final FunctionTarget? outer,
  final FunctionTarget? inner,
);

_Fixture _program({
  String kind = 'known',
  bool indirect = false,
  bool context = false,
}) {
  final store = FunctionTarget(
    _uri,
    'store',
    .integer,
    context ? [] : [.integer],
  );
  final write = Block(store.parameterTypes);
  final externals = <IrExternal>[];
  Value address = context
      ? write.emit(ReadNativeContext())
      : write.parameters.single;
  if (kind == 'loaded') address = write.emit(LoadNative(address, _i64));
  if (kind == 'external_release' || kind == 'external_write') {
    final leaf = FunctionTarget(_uri, 'native', .voidType, [
      .integer,
      .integer,
    ]);
    externals.add(
      IrExternal(
        leaf,
        effects: const {Effect.writesStorage},
        capturesArguments: false,
        memory: kind == 'external_release'
            ? const ExternalMemory.release(0, 1)
            : const ExternalMemory.write(0, 1),
      ),
    );
    write.emit(DirectCall(leaf, [address, const Constant.integer(8)]));
  }
  write.emit(StoreNative(address, _i64, const Constant.integer(0)));
  write.finish(const Return(Constant.integer(0)));
  final functions = <IrFunction>[
    IrFunction(store, [write]),
  ];
  FunctionTarget? inner, outer;
  if (indirect) {
    inner = FunctionTarget(_uri, 'inner', .integer, [.integer, .integer]);
    final body = Block(inner.parameterTypes);
    body.finish(
      Return(
        body.emit(
          DirectCall(store, [
            body.emit(IntBinary(.add, body.parameters[1], body.parameters[0])),
          ]),
        ),
      ),
    );
    outer = FunctionTarget(_uri, 'outer', .integer, [.integer, .integer]);
    final forward = Block(outer.parameterTypes);
    forward.finish(
      Return(
        forward.emit(
          DirectCall(inner, [forward.parameters[1], forward.parameters[0]]),
        ),
      ),
    );
    functions.addAll([
      IrFunction(inner, [body]),
      IrFunction(outer, [forward]),
    ]);
  }
  final root = FunctionTarget(
    _uri,
    'root',
    .integer,
    kind == 'unknown' ? [.integer] : [],
  );
  final block = Block(root.parameterTypes);
  final owner = block.emit(NewPayload(_bytes, const Constant.integer(24)));
  final base = block.emit(ReferenceAddress(owner));
  final payload = block.emit(
    IntBinary(.add, base, Constant.integer(_layout.objectLayout(_bytes).size)),
  );
  Value pointer = payload;
  if (kind == 'outside') {
    pointer = block.emit(IntBinary(.add, payload, const Constant.integer(24)));
  }
  if (kind == 'unknown') pointer = block.parameters.single;
  if (kind == 'loaded') {
    pointer = block.emit(IntBinary(.add, payload, const Constant.integer(8)));
    block.emit(StoreNative(pointer, _i64, payload));
  }
  if (context) block.emit(BindNativeContext(pointer));
  final cells = <Value>[];
  for (var i = 0; i < 12; i++) {
    cells.add(block.emit(NewCell(CellType(.integer), Constant.integer(i))));
    block.emit(
      DirectCall(
        outer ?? store,
        context
            ? []
            : indirect
            ? [pointer, const Constant.integer(8)]
            : [pointer],
      ),
    );
  }
  Value sum = const Constant.integer(0);
  for (final cell in cells) {
    sum = block.emit(IntBinary(.add, sum, block.emit(ReadCell(cell))));
  }
  block.finish(Return(sum));
  functions.add(IrFunction(root, [block]));
  return _Fixture(
    IrProgram([IrClass(_bytes, [])], functions, externals: externals),
    root,
    store,
    outer,
    inner,
  );
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));

  @override
  ObjectLayout objectLayout(ClassType type) =>
      ObjectLayout([.word, .reference]);
}

Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;
