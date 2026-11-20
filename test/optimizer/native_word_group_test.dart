import 'dart:ffi' show Int64, Uint8;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _i64 = NativeScalarType(Int64), _u8 = NativeScalarType(Uint8);

final class _Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}

void main() {
  for (final mutation in [
    'none',
    'unknown-offset',
    'byte',
    'word',
    'foreign-write',
    'stale-read',
  ]) {
    test('joined module words preserve matching paths ($mutation)', () {
      final uri = Uri.parse('memory:word-correlation');
      final slots = NativeData(List.filled(32, 0), alignment: 8),
          pageA = NativeData(List.filled(24, 0), alignment: 8),
          pageB = NativeData(List.filled(24, 0), alignment: 8);
      final publish = FunctionTarget(uri, 'publish', .voidType, [
            .boolean,
            .boolean,
          ]),
          reader = FunctionTarget(uri, 'observer', .integer, []);
      final start = Block(publish.parameterTypes),
          choose = Block(),
          a = Block(),
          b = Block(),
          store = Block([ValueType.integer]),
          done = Block();
      final dest = start.emit(NativeDataAddress(slots));
      start.finish(Branch(start.parameters.first, Jump(choose), Jump(done)));
      choose.finish(Branch(start.parameters.last, Jump(a), Jump(b)));
      a.finish(Jump(store, [a.emit(NativeDataAddress(pageA))]));
      b.finish(Jump(store, [b.emit(NativeDataAddress(pageB))]));
      final page = store.parameters.single;
      store.emit(StoreNative(dest, _i64, page));
      store.emit(
        StoreNative(
          store.emit(IntBinary(.add, dest, const Constant.integer(16))),
          _i64,
          store.emit(
            IntBinary(
              .add,
              page,
              Constant.integer(mutation == 'unknown-offset' ? -8 : 8),
            ),
          ),
        ),
      );
      store.finish(Jump(done));
      done.finish(const Return());
      final block = Block(), onZero = Block(), present = Block();
      final p = block.emit(NativeDataAddress(slots)),
          q = block.emit(IntBinary(.add, p, const Constant.integer(16)));
      final before = block.emit(LoadNative(p, _i64));
      final mark = block.emit(LoadNative(q, _i64));
      final external = FunctionTarget(uri, 'externalWrite', .voidType, [
        .integer,
        .integer,
      ]);
      if (mutation == 'byte')
        block.emit(
          StoreNative(
            block.emit(IntBinary(.add, p, const Constant.integer(1))),
            _u8,
            const Constant.integer(1),
          ),
        );
      if (mutation == 'word')
        block.emit(StoreNative(p, _i64, const Constant.integer(99)));
      if (mutation == 'foreign-write')
        block.emit(DirectCall(external, [p, const Constant.integer(8)]));
      if (mutation == 'stale-read')
        block.emit(StoreNative(q, _i64, const Constant.integer(9)));
      block.finish(
        Branch(
          block.emit(Equals(mark, const Constant.integer(0))),
          Jump(onZero),
          Jump(present),
        ),
      );
      final rz = onZero.emit(LoadNative(p, _i64)),
          rp = present.emit(LoadNative(p, _i64));
      final ze = onZero.emit(Equals(before, const Constant.integer(0))),
          pe = present.emit(Equals(before, const Constant.integer(0)));
      onZero.finish(Return(rz));
      present.finish(Return(rp));
      final program = IrProgram(
        [],
        [
          IrFunction(publish, [start, choose, a, b, store, done]),
          IrFunction(reader, [block, onZero, present]),
        ],
        externals: [
          IrExternal(
            external,
            effects: {Effect.writesStorage},
            memory: const ExternalMemory.write(0, 1),
          ),
        ],
      );
      final facts = ProgramFlow(
        program,
        [],
        openEntries: [publish, reader],
        memoryLayout: _Layout(),
      ).facts;
      expect(facts.reachesBlock(onZero), isTrue);
      expect(facts.reachesBlock(present), isTrue);
      if (mutation == 'none') {
        expect(facts.valueOf(rz).constant, const Constant.integer(0));
        expect(facts.valueOf(rp).addresses, hasLength(2));
        expect(facts.valueOf(rp).constants, isEmpty);
        expect((facts.valueOf(ze).constant as ScalarConstant?)?.value, true);
        expect((facts.valueOf(pe).constant as ScalarConstant?)?.value, false);
      } else if (mutation == 'unknown-offset') {
        expect(facts.valueOf(rz).addresses, hasLength(2));
        expect(
          facts.valueOf(rz).constants,
          contains(const Constant.integer(0)),
        );
        expect(facts.valueOf(rp).addresses, hasLength(2));

      } else if (mutation == 'word') {
        expect(facts.valueOf(rp).constant, const Constant.integer(99));
        expect(facts.valueOf(rz).constant, const Constant.integer(99));
      } else if (mutation == 'byte' || mutation == 'foreign-write') {
        expect(facts.valueOf(rz).constant, isNull);
      } else {
        expect(facts.valueOf(rz).constant, isNull);
        expect(
          facts.valueOf(rp).constants,
          contains(const Constant.integer(0)),
        );
      }
    });
  }
  for (final mode in ['word', 'copy', 'call']) {
    test('a rebuilt group never rebinds an earlier read ($mode)', () {
      final uri = Uri.parse('memory:replaced-native-words');
      final slots = NativeData(List.filled(32, 0), alignment: 8),
          backing = NativeData(List.filled(16, 0), alignment: 8),
          buffer = NativeData(List.filled(8, 0), alignment: 8);
      final store = FunctionTarget(uri, 'writePair', .voidType, [
        .integer,
        .integer,
        .integer,
      ]);
      final def = Block(store.parameterTypes);
      def.emit(StoreNative(def.parameters[0], _i64, def.parameters[2]));
      def.emit(StoreNative(def.parameters[1], _i64, def.parameters[2]));
      def.finish(const Return());
      final root = FunctionTarget(uri, 'observe', .integer, [.boolean]),
          start = Block(root.parameterTypes),
          cold = Block(),
          warm = Block(),
          first = Block(),
          becomeWarm = Block(),
          becomeCold = Block(),
          second = Block(),
          nowZero = Block(),
          nowWarm = Block();
      final p = start.emit(NativeDataAddress(slots)),
          q = start.emit(IntBinary(.add, p, const Constant.integer(16))),
          addr = start.emit(NativeDataAddress(backing)),
          temp = start.emit(NativeDataAddress(buffer));
      void write(Block b, Value v, {required bool replace}) {
        if (replace && mode == 'copy') {
          b.emit(StoreNative(temp, _i64, v));
          b.emit(CopyNative(p, temp, _i64));
          b.emit(CopyNative(q, temp, _i64));
        } else if (replace && mode == 'call') {
          b.emit(DirectCall(store, [p, q, v]));
        } else {
          b.emit(StoreNative(p, _i64, v));
          b.emit(StoreNative(q, _i64, v));
        }
      }

      start.finish(Branch(start.parameters.single, Jump(cold), Jump(warm)));
      write(cold, const Constant.integer(0), replace: false);
      cold.finish(Jump(first));
      write(warm, addr, replace: false);
      warm.finish(Jump(first));
      final old = first.emit(LoadNative(p, _i64));
      first.finish(
        Branch(
          first.emit(Equals(old, const Constant.integer(0))),
          Jump(becomeWarm),
          Jump(becomeCold),
        ),
      );
      write(becomeWarm, addr, replace: true);
      becomeWarm.finish(Jump(second));
      write(becomeCold, const Constant.integer(0), replace: true);
      becomeCold.finish(Jump(second));
      final fresh = second.emit(LoadNative(p, _i64)),
          guard = second.emit(LoadNative(q, _i64));
      second.finish(
        Branch(
          second.emit(Equals(guard, const Constant.integer(0))),
          Jump(nowZero),
          Jump(nowWarm),
        ),
      );
      final zOld = nowZero.emit(Equals(old, const Constant.integer(0))),
          zNew = nowZero.emit(Equals(fresh, const Constant.integer(0)));
      final wOld = nowWarm.emit(Equals(old, const Constant.integer(0))),
          wNew = nowWarm.emit(Equals(fresh, const Constant.integer(0)));
      nowZero.finish(const Return(Constant.integer(0)));
      nowWarm.finish(const Return(Constant.integer(1)));
      final f = IrFunction(root, [
        start,
        cold,
        warm,
        first,
        becomeWarm,
        becomeCold,
        second,
        nowZero,
        nowWarm,
      ]);
      final graph = IrProgram([], [
        f,
        IrFunction(store, [def]),
      ]);
      final facts = ProgramFlow(graph, [
        (target: root, arguments: [FlowValue.unknown(.boolean)]),
      ], memoryLayout: _Layout()).facts;
      bool? observed(Value v) =>
          (facts.valueOf(v).constant as ScalarConstant?)?.value as bool?;
      expect(facts.reachesBlock(nowWarm), isTrue);
      expect(facts.reachesBlock(nowZero), isTrue);
      // An old zero selected the stores of addr; an old addr selected both zero stores.
      expect(observed(zOld), isNot(true));
      expect(observed(wOld), isNot(false));
      expect(observed(zNew), isTrue);
      expect(observed(wNew), isFalse);
    });
  }
  test('an external callback can re-enter a writer after native loads', () {
    final uri = Uri.parse('memory:raw-reentry');
    final slots = NativeData(List.filled(24, 0), alignment: 8),
        base = NativeData(List.filled(16, 0), alignment: 8);
    final write = FunctionTarget(uri, 'overwrite', .voidType, []);
    final modify = Block();
    modify.emit(
      StoreNative(
        modify.emit(NativeDataAddress(slots)),
        _i64,
        const Constant.integer(91),
      ),
    );
    modify.finish(const Return());
    final root = FunctionTarget(uri, 'observe', .integer, [
      .boolean,
      write.signature,
    ]);
    final start = Block(root.parameterTypes),
        placed = Block(),
        join = Block(),
        zero = Block(),
        warm = Block();
    final p = start.emit(NativeDataAddress(slots)),
        q = start.emit(IntBinary(.add, p, const Constant.integer(16))),
        address = start.emit(NativeDataAddress(base));
    start.finish(Branch(start.parameters.first, Jump(placed), Jump(join)));
    placed.emit(StoreNative(p, _i64, address));
    placed.emit(StoreNative(q, _i64, address));
    placed.finish(Jump(join));
    final old = join.emit(LoadNative(p, _i64)),
        marker = join.emit(LoadNative(q, _i64));
    final call = join.emit(FunctionCall(start.parameters.last, const []));
    join.finish(
      Branch(
        join.emit(Equals(marker, const Constant.integer(0))),
        Jump(zero),
        Jump(warm),
      ),
    );
    final a = zero.emit(LoadNative(p, _i64)),
        b = warm.emit(LoadNative(p, _i64));
    zero.emit(KeepAlive(old));
    warm.emit(KeepAlive(old));
    zero.finish(Return(a));
    warm.finish(Return(b));
    final prog = IrProgram([], [
      IrFunction(root, [start, placed, join, zero, warm]),
      IrFunction(write, [modify]),
    ]);
    final facts = ProgramFlow(prog, [
      (
        target: root,
        arguments: [
          FlowValue.unknown(.boolean),
          FlowValue.unknown(
            write.signature,
            external: true,
          ).join(FlowValue.constant(FunctionConstant(write))),
        ],
      ),
    ], memoryLayout: _Layout()).facts;
    expect(facts.hasUnknownCall(call), isTrue);
    expect(facts.targetsOf(call), contains(write));
    for (final v in [a, b]) {
      final result = facts.valueOf(v);
      expect(
        result.unknownTypes.contains(ValueType.integer) ||
            result.constants.any((c) => c is ScalarConstant && c.value == 91),
        isTrue,
      );
    }
  });
}
