import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('host writes a pointer obtained from its first callback before its second callback', () {
    final uri = Uri.parse('memory:interleaved-write');
    final saved = GlobalVariable(uri, 'address', .integer, isLate: true),
        marker = GlobalVariable(uri, 'marker', .integer, isLate: true);
    final produce = FunctionTarget(uri, 'produce', .integer, []),
        check = FunctionTarget(uri, 'check', .voidType, []);
    final map = FunctionTarget(uri, 'map', .integer, [.integer]),
        host = FunctionTarget(uri, 'host', .voidType, [
          produce.signature,
          check.signature,
        ]);
    final raw = NativeScalarType(Int64),
        make = Block(),
        consumer = Block(),
        use = Block(),
        set = Block(),
        done = Block();
    final ptr = make.emit(DirectCall(map, [const Constant.integer(8)]));
    make.emit(StoreGlobal(saved, ptr));
    make.finish(Return(ptr));
    final record = consumer.emit(LoadGlobal(saved));
    consumer.finish(
      Branch(
        consumer.emit(Equals(record, const Constant.integer(0))),
        Jump(done),
        Jump(use),
      ),
    );
    final word = use.emit(LoadNative(record, raw));
    use.finish(
      Branch(
        use.emit(Equals(word, const Constant.integer(99))),
        Jump(set),
        Jump(done),
      ),
    );
    set.emit(StoreGlobal(marker, const Constant.integer(91)));
    set.finish(const Return());
    done.finish(const Return());
    final root = FunctionTarget(uri, 'run', .integer, []), b = Block();
    b.emit(StoreGlobal(saved, const Constant.integer(0)));
    b.emit(StoreGlobal(marker, const Constant.integer(3)));
    b.emit(
      DirectCall(host, [FunctionConstant(produce), FunctionConstant(check)]),
    );
    b.finish(Return(b.emit(LoadGlobal(marker))));
    final makeFn = IrFunction(produce, [make]),
        checkFn = IrFunction(check, [consumer, use, set, done]),
        run = IrFunction(root, [b]);
    final p = IrProgram(
      [],
      [run, makeFn, checkFn],
      globals: [saved, marker],
      externals: [
        IrExternal(
          map,
          effects: {},
          memory: const .zeroed(0),
          capturesArguments: false,
        ),
        IrExternal(
          host,
          effects: {Effect.writesStorage, Effect.callsUserCode},
          capturesArguments: false,
        ),
      ],
    );
    final f = ProgramFlow(p, [
      (target: root, arguments: []),
    ], memoryLayout: _Layout()).facts;
    final result = f.returnedBy(root).integers!;
    final lib = DynamicLibrary.process();
    final calloc = lib
        .lookupFunction<
          Pointer<Void> Function(IntPtr, IntPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    final free = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final allocated = <Pointer<Void>>[];
    late IrInterpreter machine;
    machine = IrInterpreter(
      p,
      {},
      externalCalls: {
        map: (args) {
          final p = calloc(1, args.single as int);
          allocated.add(p);
          return p.address;
        },
        host: (_) {
          final ptr = machine.run(makeFn, []) as int;
          Pointer<Int64>.fromAddress(ptr).value = 99;
          machine.run(checkFn, []);
          return null;
        },
      },
    );
    try {
      final concrete = machine.run(run, []);
      expect(concrete, 91);
      expect(result.contains(91), isTrue);
    } finally {
      for (final pointer in allocated) {
        free(pointer);
      }
    }
  });
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(Target.host());
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}
