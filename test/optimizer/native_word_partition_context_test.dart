import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final class Layout implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([]);
}

void main() {
  test('different orders of the same committed bytes and word constraints share the callee input', () {
    final word = NativeScalarType(Int64);
    final memory = NativeData(List.filled(24, 0), alignment: 8);
    final helper = FunctionTarget(null, 'observe', .integer, []);
    final observe = Block();
    final data = observe.emit(NativeDataAddress(memory));
    final p = observe.emit(LoadNative(data, word));
    final q = observe.emit(
      LoadNative(
        observe.emit(IntBinary(.add, data, const Constant.integer(8))),
        word,
      ),
    );
    observe.finish(Return(observe.emit(IntBinary(.add, p, q))));
    final functions = <IrFunction>[
      IrFunction(helper, [observe]),
    ];
    final roots = <({FunctionTarget target, List<FlowValue> arguments})>[];
    for (final writeFirst in [true, false]) {
      final root = FunctionTarget(null, 'enter$writeFirst', .integer, [
        .boolean,
      ]);
      final entry = Block(root.parameterTypes),
          hot = Block(),
          cold = Block(),
          merge = Block();
      final address = entry.emit(NativeDataAddress(memory));
      if (writeFirst)
        entry.emit(StoreNative(address, word, const Constant.integer(77)));
      entry.finish(Branch(entry.parameters.single, Jump(hot), Jump(cold)));
      for (var i = writeFirst ? 1 : 0; i < 3; i++)
        hot.emit(
          StoreNative(
            hot.emit(IntBinary(.add, address, Constant.integer(8 * i))),
            word,
            Constant.integer(10 + i),
          ),
        );
      hot.finish(Jump(merge));
      cold.finish(Jump(merge));
      if (!writeFirst)
        merge.emit(StoreNative(address, word, const Constant.integer(77)));
      merge.finish(Return(merge.emit(DirectCall(helper, []))));
      functions.add(IrFunction(root, [entry, hot, cold, merge]));
      roots.add((target: root, arguments: [FlowValue.unknown(.boolean)]));
    }
    final f = ProgramFlow(
      IrProgram([], functions),
      roots,
      memoryLayout: Layout(),
    ).facts;
    for (final r in roots) {
      final range = f.returnedBy(r.target).integers!;
      expect(range.contains(77), isTrue);
      expect(range.contains(88), isTrue);
    }
    print('helper activations=${f.activationsOf(helper).length}');
    expect(f.activationsOf(helper), hasLength(1));
  });
}
