import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout/memory.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/control.dart' show ControlBlock;
import '../support/runtime.dart';

void main() {
  test('native cleanup reads the selected live mapping after either throw', () async {
    await prepareRuntime('test/compiler/fixtures/same_heap_finalizer.dart');
    final sdk = ProgramNormalization(heapRuntime.program, runtime: heapRuntime).run();
    final map = heapRuntime.primitives.entries.singleWhere((e) => e.value == .map).key;
    final unmap = heapRuntime.primitives.entries.singleWhere((e) => e.value == .unmap).key;
    final release = sdk.functions.singleWhere((body) =>
        body.target.name == 'releaseControl' &&
        body.target.library.toString().endsWith('/sdk/runtime/control.dart'));
    final unmapCall = [
      for (final block in release.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    ].whereType<DirectCall>().singleWhere((call) => call.target == unmap);
    final capacity = unmapCall.inputs.last as LoadNative;
    final layout = NativeLayout(Target.host());
    final word = NativeScalarType(Int64);
    final library = Uri.parse('memory:cleanup');
    const zero = Constant.integer(0), failure = Constant.integer(99);
    const initialSize = Constant.integer(37), replacementSize = Constant.integer(123);
    Value head(Block block, Value context) => block.emit(
        IntBinary(.add, context, const Constant.integer(RuntimeContext.bootstrap)));

    final signature = [ValueType.integer, ValueType.boolean];
    final init = FunctionTarget(library, 'initialize', .integer, signature);
    final check = Block(signature), dispose = Block(), ready = Block();
    check.finish(Branch(check.parameters.last, Jump(dispose), Jump(ready)));
    final slot = head(dispose, check.parameters.first);
    final old = dispose.emit(LoadNative(slot, word));
    dispose.emit(DirectCall(unmap, [old, initialSize]));
    dispose.emit(StoreNative(slot, word, zero));
    dispose.finish(Throw(failure));
    ready.finish(Return(check.parameters.first));

    final fail = FunctionTarget(library, 'fail', .integer, [.integer]);
    final raise = Block(fail.parameterTypes)..finish(Throw(failure));
    final allocate = FunctionTarget(library, 'allocate', .integer, signature);
    final sequence = Block(signature);
    final initialized = sequence.emit(DirectCall(init, sequence.parameters));
    sequence.finish(Return(sequence.emit(DirectCall(fail, [initialized]))));
    IrFunction forward(String name, FunctionTarget callee) {
      final target = FunctionTarget(library, name, .integer, signature);
      final block = Block(signature);
      block.finish(Return(block.emit(DirectCall(callee, block.parameters))));
      return IrFunction(target, [block]);
    }

    final grow = forward('grow', allocate), exported = forward('exported', grow.target);
    final replace = FunctionTarget(library, 'replace', .voidType, [.integer, .integer]);
    final change = Block(replace.parameterTypes);
    change.emit(StoreNative(head(change, change.parameters.first), word, change.parameters.last));
    change.finish(const Return());

    for (final replaceHead in [false, true]) {
      final target = FunctionTarget(library, 'entry', .voidType, [.boolean]);
      final entry = Block(target.parameterTypes), first = Block(), second = Block(), setup = Block();
      final done = Block()..finish(const Return());
      Value mapping(Block block, Constant size, Block next) {
        final address = block.emit(DirectCall(map, [size]));
        block.finish(Branch(block.emit(Equals(address, zero)), Jump(done), Jump(next)));
        return address;
      }
      final context = mapping(entry, const Constant.integer(RuntimeContext.size), first);
      final a = mapping(first, initialSize, second);
      final b = mapping(second, replacementSize, setup);
      setup.emit(StoreNative(head(setup, context), word, a));
      // Zeroed mappings already terminate the linked list at offset zero.
      Value capacitySlot(Value address) => setup.emit(IntBinary(.add, address, const Constant.integer(ControlBlock.capacity)));
      setup.emit(StoreNative(capacitySlot(a), word, initialSize));
      setup.emit(StoreNative(capacitySlot(b), word, replacementSize));
      final caught = Block([ValueType.object]), cleanup = Block(), other = Block(), report = Block();
      setup.finish(Invoke(DirectCall(exported.target, [context, entry.parameters.single]),
          onReturn: Jump(done), onThrow: Jump(caught, [UnwindValue.exception])));
      caught.finish(Branch(caught.emit(Equals(caught.parameters.single, failure)), Jump(cleanup), Jump(other)));
      other.finish(Throw(caught.parameters.single));
      if (replaceHead) cleanup.emit(DirectCall(replace, [context, b]));
      cleanup.finish(Jump(report));
      report.emit(DirectCall(release.target, [context]));
      report.finish(const Return());
      final graph = IrProgram(sdk.classes, [
        ...sdk.functions,
        IrFunction(target, [entry, first, second, setup, done, caught, cleanup, other, report]),
        IrFunction(init, [check, dispose, ready]), IrFunction(fail, [raise]),
        IrFunction(allocate, [sequence]), grow, exported,
        if (replaceHead) IrFunction(replace, [change]),
      ], globals: sdk.globals, externals: sdk.externals,
          nativeBoundaries: sdk.nativeBoundaries, executionShapes: sdk.executionShapes);
      final facts = ProgramFlow(graph, [(target: target, arguments: [FlowValue.unknown(.boolean)])],
          memoryLayout: ProgramLayout(graph.classes, nativeLayout: layout,
              functions: graph.functions, typeRuntime: heapRuntime.types)).facts;
      final expected = replaceHead ? 123 : 37;
      expect(facts.reachesOperation(unmapCall), isTrue);
      expect(facts.valueOf(capacity).integers, FlowIntegerRange(expected, expected));
    }
  });
}
