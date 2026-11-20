import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _i64 = NativeScalarType(Int64);
const _zero = Constant.integer(0), _word = Constant.integer(8);

final class _Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}

void main() {
  test('a zero successor cannot release the previous allocation a second time', () {
    final uri = Uri.parse('memory:guarded-release');
    final saved = GlobalVariable(uri, 'saved', .integer, isLate: true);
    final allocate = FunctionTarget(uri, 'allocate', .integer, [.integer]);
    final release = FunctionTarget(uri, 'release', .voidType, [
      .integer,
      .integer,
    ]);
    final root = FunctionTarget(uri, 'root', .integer, []);
    final start = Block(),
        fill = Block(),
        header = Block([ValueType.integer]),
        body = Block(),
        done = Block(),
        failed = Block();
    start.emit(StoreGlobal(saved, const Constant.integer(37)));
    const capacity = Constant.integer(16);
    final base = start.emit(DirectCall(allocate, [capacity]));
    start.finish(
      Branch(start.emit(Equals(base, _zero)), Jump(failed), Jump(fill)),
    );
    failed.finish(const Return(Constant.integer(-1)));
    fill.emit(StoreNative(base, _i64, _zero));
    fill.emit(
      StoreNative(fill.emit(IntBinary(.add, base, _word)), _i64, capacity),
    );
    fill.finish(Jump(header, [base]));
    final cursor = header.parameters.single;
    header.finish(
      Branch(
        header.emit(Equals(cursor, _zero, negated: true)),
        Jump(body),
        Jump(done),
      ),
    );
    final next = body.emit(LoadNative(cursor, _i64));
    final length = body.emit(
      LoadNative(body.emit(IntBinary(.add, cursor, _word)), _i64),
    );
    final free = body.emit(DirectCall(release, [cursor, length]));
    body.finish(Jump(header, [next]));
    final privateValue = done.emit(LoadGlobal(saved));
    done.finish(Return(privateValue));
    final graph = IrProgram(
      [],
      [
        IrFunction(root, [start, fill, header, body, done, failed]),
      ],
      globals: [saved],
      externals: [
        IrExternal(
          allocate,
          effects: const {.writesStorage},
          memory: const .zeroed(0),
        ),
        IrExternal(
          release,
          effects: const {.writesStorage},
          capturesArguments: false,
          memory: const ExternalMemory.release(0, 1),
        ),
      ],
    );
    final f = ProgramFlow(graph, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _Layout()).facts;
    final n = f.valueOf(next).integers,
        len = f.valueOf(length).integers,
        g = f.valueOf(privateValue).integers;
    print(
      'next=[${n?.lower},${n?.upper}] length=[${len?.lower},${len?.upper}] private=[${g?.lower},${g?.upper}] release=${f.reachesOperation(free)}',
    );
    expect(f.reachesOperation(free), isTrue);
    expect(f.reachesBlock(done), isTrue);
    expect([n?.constant, len?.constant, g?.constant], [0, 16, 37]);
  });
}
