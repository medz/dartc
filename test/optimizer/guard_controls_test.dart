import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final uri = Uri.parse('memory:guard-controls');
final i64 = NativeScalarType(Int64);
const zero = Constant.integer(0), word = Constant.integer(8);

class Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([.word]);
}

final reserve = FunctionTarget(uri, 'reserve', .integer, [.integer]);
final release = FunctionTarget(uri, 'release', .voidType, [.integer, .integer]);
final externals = [
  IrExternal(
    reserve,
    effects: const {.writesStorage},
    memory: const .zeroed(0),
  ),
  IrExternal(
    release,
    effects: const {.writesStorage},
    capturesArguments: false,
    memory: const .release(0, 1),
  ),
];
FlowValue val(int n) => FlowValue.constant(Constant.integer(n));
void has(FlowValue input, List<int> values) {
  final range = input.integers;
  expect(range, isNotNull);
  for (final value in values) {
    expect(
      range!.contains(value),
      isTrue,
      reason: 'missing $value in [${range.lower},${range.upper}]',
    );
  }
}

void main() {
  test(
    'the next nonzero region really reenters and may have a different capacity',
    () {
      final root = FunctionTarget(uri, 'chain', .integer, []);
      final a = Block(),
          b = Block(),
          fill = Block(),
          header = Block([ValueType.integer]),
          body = Block(),
          at24 = Block(),
          atOther = Block(),
          done = Block(),
          fail = Block();
      final first = a.emit(DirectCall(reserve, [const Constant.integer(16)]));
      a.finish(Branch(a.emit(Equals(first, zero)), Jump(fail), Jump(b)));
      final second = b.emit(DirectCall(reserve, [const Constant.integer(24)]));
      b.finish(Branch(b.emit(Equals(second, zero)), Jump(fail), Jump(fill)));
      fail.finish(const Return(Constant.integer(-1)));
      fill.emit(StoreNative(first, i64, second));
      fill.emit(
        StoreNative(
          fill.emit(IntBinary(.add, first, word)),
          i64,
          const Constant.integer(16),
        ),
      );
      fill.emit(StoreNative(second, i64, zero));
      fill.emit(
        StoreNative(
          fill.emit(IntBinary(.add, second, word)),
          i64,
          const Constant.integer(24),
        ),
      );
      fill.finish(Jump(header, [first]));
      final p = header.parameters.single;
      header.finish(
        Branch(
          header.emit(Equals(p, zero, negated: true)),
          Jump(body),
          Jump(done),
        ),
      );
      final next = body.emit(LoadNative(p, i64));
      final size = body.emit(
        LoadNative(body.emit(IntBinary(.add, p, word)), i64),
      );
      final freed = body.emit(DirectCall(release, [p, size]));
      body.finish(
        Branch(
          body.emit(Equals(size, const Constant.integer(24))),
          Jump(at24),
          Jump(atOther),
        ),
      );
      at24.finish(Jump(header, [next]));
      atOther.finish(Jump(header, [next]));
      done.finish(const Return(Constant.integer(37)));
      final graph = IrProgram([], [
        IrFunction(root, [a, b, fill, header, body, at24, atOther, done, fail]),
      ], externals: externals);
      final f = ProgramFlow(graph, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: Layout()).facts;
      expect(f.reachesBlock(at24), isTrue);
      expect(f.reachesBlock(atOther), isTrue);
      expect(f.reachesBlock(done), isTrue);
      expect(f.reachesOperation(freed), isTrue);
      has(f.valueOf(size), [16, 24]);
      expect(f.valueOf(p).addresses.length, greaterThanOrEqualTo(2));
    },
  );

  for (final throws in [false, true]) {
    test(
      'user-defined equality writes its global and preserves its ${throws ? 'exceptional' : 'normal'} result',
      () {
        final owner = ClassType(uri, 'Checker');
        final seen = GlobalVariable(uri, 'seen', .integer, isLate: true);
        final equality = FunctionTarget(
          uri,
          '==',
          .boolean,
          [.object],
          owner: owner,
          kind: .method,
        );
        final impl = Block(equality.parameterTypes);
        impl.emit(StoreGlobal(seen, const Constant.integer(9)));
        impl.finish(
          throws
              ? Throw(const Constant.string('equality failed'))
              : const Return(Constant.boolean(false)),
        );
        final loop = FunctionTarget(uri, 'loop', .integer, []);
        final first = Block(),
            header = Block([ValueType.object]),
            body = Block(),
            out = Block();
        first.finish(Jump(header, [ObjectConstant(owner, {})]));
        final cmp = header.emit(
          Equals(header.parameters.single, zero, negated: true),
        );
        header.finish(Branch(cmp, Jump(body), Jump(out)));
        body.finish(Jump(header, [zero]));
        out.finish(Return(out.emit(LoadGlobal(seen))));
        final root = FunctionTarget(uri, 'root', .integer, []);
        final entry = Block(), ok = Block([ValueType.integer]), err = Block();
        entry.emit(StoreGlobal(seen, const Constant.integer(1)));
        final invoke = DirectCall(loop, []);
        entry.finish(
          Invoke(invoke, onReturn: Jump(ok, [invoke]), onThrow: Jump(err)),
        );
        ok.finish(Return(ok.parameters.single));
        err.finish(
          Return(
            err.emit(
              IntBinary(
                .add,
                err.emit(LoadGlobal(seen)),
                const Constant.integer(100),
              ),
            ),
          ),
        );
        final graph = IrProgram(
          [
            IrClass(owner, [], members: [equality]),
          ],
          [
            IrFunction(root, [entry, ok, err]),
            IrFunction(loop, [first, header, body, out]),
            IrFunction(equality, [impl]),
          ],
          globals: [seen],
        );
        final f = ProgramFlow(graph, [
          (target: root, arguments: <FlowValue>[]),
        ]).facts;
        expect(f.activationsOf(equality), isNotEmpty);
        if (throws) {
          expect(f.reachesBlock(err), isTrue);
        } else {
          expect(f.reachesBlock(ok), isTrue);
        }
        has(f.returnedBy(root), [throws ? 109 : 9]);
        expect(
          IrInterpreter(graph, {}).run(graph.functions.first, []),
          throws ? 109 : 9,
        );
      },
    );
  }

  test('unknown incoming aliases initialized before and after allocation stay distinguishable', () {
    final root = FunctionTarget(uri, 'aliases', .integer, [.boolean]);
    final a = Block(root.parameterTypes),
        b = Block(),
        choose = Block(),
        left = Block(),
        right = Block(),
        header = Block([ValueType.integer]),
        write = Block(),
        done = Block(),
        fail = Block();
    final before = a.emit(DirectCall(reserve, [word]));
    a.finish(Branch(a.emit(Equals(before, zero)), Jump(fail), Jump(b)));
    b.emit(StoreNative(before, i64, const Constant.integer(13)));
    final after = b.emit(DirectCall(reserve, [word]));
    b.finish(Branch(b.emit(Equals(after, zero)), Jump(fail), Jump(choose)));
    choose.emit(StoreNative(after, i64, const Constant.integer(19)));
    choose.finish(Branch(a.parameters.single, Jump(left), Jump(right)));
    left.finish(Jump(header, [before]));
    right.finish(Jump(header, [after]));
    final p = header.parameters.single;
    header.finish(
      Branch(
        header.emit(Equals(p, zero, negated: true)),
        Jump(write),
        Jump(done),
      ),
    );
    write.emit(StoreNative(p, i64, const Constant.integer(73)));
    write.finish(Jump(header, [zero]));
    final aValue = done.emit(LoadNative(before, i64)),
        bValue = done.emit(LoadNative(after, i64));
    done.finish(Return(done.emit(IntBinary(.add, aValue, bValue))));
    fail.finish(const Return(Constant.integer(-1)));
    final graph = IrProgram([], [
      IrFunction(root, [a, b, choose, left, right, header, write, done, fail]),
    ], externals: externals);
    final f = ProgramFlow(graph, [
      (target: root, arguments: [FlowValue.unknown(.boolean)]),
    ], memoryLayout: Layout()).facts;
    has(f.valueOf(aValue), [13, 73]);
    has(f.valueOf(bValue), [19, 73]);
    expect(f.valueOf(p).addresses.length, greaterThanOrEqualTo(2));
  });
  test('a previously constant entry becomes unknown and reopens both guard outcomes', () {
    final root = FunctionTarget(uri, 'widen', .integer, [.integer]);
    final saved = GlobalVariable(uri, 'result', .integer, isLate: true);
    final start = Block(root.parameterTypes),
        header = Block([ValueType.integer]),
        work = Block(),
        done = Block();
    start.emit(StoreGlobal(saved, const Constant.integer(13)));
    start.finish(Jump(header, start.parameters));
    final p = header.parameters.single;
    header.finish(
      Branch(
        header.emit(Equals(p, zero, negated: true)),
        Jump(work),
        Jump(done),
      ),
    );
    work.emit(StoreGlobal(saved, const Constant.integer(73)));
    work.finish(Jump(header, [zero]));
    final result = done.emit(LoadGlobal(saved));
    done.finish(Return(result));
    final graph = IrProgram(
      [],
      [
        IrFunction(root, [start, header, work, done]),
      ],
      globals: [saved],
    );
    final flow = ProgramFlow(graph, [
      (target: root, arguments: [val(0)]),
    ]);
    expect(flow.facts.reachesBlock(work), isFalse);
    expect(flow.facts.valueOf(result).integers?.constant, 13);
    flow.extend(
      entries: [
        (target: root, arguments: [FlowValue.unknown(.integer)]),
      ],
    );
    expect(flow.facts.reachesBlock(work), isTrue);
    has(flow.facts.valueOf(result), [13, 73]);
  });

  test(
    'a guard reloads a boxed scalar after writes through its live backing',
    () {
      final root = FunctionTarget(uri, 'boxed', .integer, [.integer]);
      final saved = GlobalVariable(uri, 'visited', .integer, isLate: true);
      final start = Block(root.parameterTypes),
          header = Block([ValueType.integer]),
          work = Block(),
          done = Block();
      start.emit(StoreGlobal(saved, const Constant.integer(13)));
      final box = start.emit(MaterializeValue(start.parameters.single));
      final raw = start.emit(ReferenceAddress(box));
      final slot = start.emit(
        IntBinary(.add, raw, const Constant.integer(ObjectHeader.fieldsOffset)),
      );
      start.finish(Jump(header, [box]));
      header.finish(
        Branch(
          header.emit(Equals(header.parameters.single, zero, negated: true)),
          Jump(work),
          Jump(done),
        ),
      );
      work.emit(StoreGlobal(saved, const Constant.integer(73)));
      work.emit(StoreNative(slot, i64, zero));
      work.finish(Jump(header, [box]));
      final result = done.emit(LoadGlobal(saved));
      done.finish(Return(result));
      final graph = IrProgram(
        [IrClass(ValueType.integer, [])],
        [
          IrFunction(root, [start, header, work, done]),
        ],
        globals: [saved],
      );
      final f = ProgramFlow(graph, [
        (
          target: root,
          arguments: [FlowValue.integerRange(FlowIntegerRange(8, 16))],
        ),
      ], memoryLayout: Layout()).facts;
      expect(f.reachesBlock(work), isTrue);
      expect(f.reachesBlock(done), isTrue);
      has(f.valueOf(result), [73]);
    },
  );
  test('an additional observable header write is visible on its exit', () {
    final root = FunctionTarget(uri, 'headerWrite', .integer, []);
    final marker = GlobalVariable(uri, 'marker', .integer, isLate: true);
    final start = Block(),
        header = Block([ValueType.integer]),
        body = Block(),
        done = Block();
    start.emit(StoreGlobal(marker, const Constant.integer(7)));
    start.finish(Jump(header, [const Constant.integer(1)]));
    header.emit(StoreGlobal(marker, const Constant.integer(91)));
    final cursor = header.parameters.single;
    header.finish(
      Branch(
        header.emit(Equals(cursor, zero, negated: true)),
        Jump(body),
        Jump(done),
      ),
    );
    body.finish(Jump(header, [zero]));
    done.finish(Return(done.emit(LoadGlobal(marker))));
    final graph = IrProgram(
      [],
      [
        IrFunction(root, [start, header, body, done]),
      ],
      globals: [marker],
    );
    final facts = ProgramFlow(graph, [
      (target: root, arguments: <FlowValue>[]),
    ]).facts;
    expect(facts.returnedBy(root).integers?.constant, 91);
    expect(IrInterpreter(graph, {}).run(graph.functions.single, []), 91);
  });
}
