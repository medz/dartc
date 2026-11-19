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
