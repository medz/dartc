import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test(
    'actual allocator IR preserves earlier writes and skips the failed commit',
    () {
      final uri = Uri.parse('memory:materialization-order');
      final ledger = GlobalVariable(uri, 'ledger', .integer, isLate: true);
      final destination = GlobalVariable(uri, 'destination', .integer.nullable);
      final target = FunctionTarget(uri, 'store', .integer, [.integer]);
      final entry = Block(target.parameterTypes),
          success = Block([.integer]),
          failure = Block();
      entry.emit(StoreGlobal(ledger, const Constant.integer(1)));
      entry.emit(StoreGlobal(destination, const Constant.integer(7)));
      final materialize = MaterializeValue(entry.parameters.single);
      entry.finish(
        Invoke(
          materialize,
          onReturn: Jump(success, [materialize]),
          onThrow: Jump(failure),
        ),
      );
      success.emit(StoreGlobal(destination, success.parameters.single));
      success.finish(const Return(Constant.integer(2)));
      final before = failure.emit(LoadGlobal(ledger));
      final retained = failure.emit(
        TypeCast(failure.emit(LoadGlobal(destination)), .integer),
      );
      failure.finish(Return(failure.emit(IntBinary(.add, before, retained))));
      final allocate = Block(heapRuntime.allocate.parameterTypes)
        ..finish(Throw(const Constant.string('allocation failed')));
      final query = heapRuntime.context;
      final queryBody = query == null
          ? null
          : (Block(query.parameterTypes)
              ..finish(const Return(Constant.integer(1))));
      final program = IrProgram(
        heapRuntime.program.classes,
        [
          for (final function in heapRuntime.program.functions)
            if (function.target == heapRuntime.allocate)
              IrFunction(function.target, [
                allocate,
              ], defaults: function.defaults)
            else if (queryBody != null && function.target == query)
              IrFunction(function.target, [
                queryBody,
              ], defaults: function.defaults)
            else
              function,
          IrFunction(target, [entry, success, failure]),
        ],
        globals: [...heapRuntime.program.globals, ledger, destination],
        externals: heapRuntime.program.externals,
      );
      final lowered = AllocationLowering(heapRuntime.rebind(program))
          .lower(program, [target]);
      final body = lowered.implementationOf(target) as IrFunction;
      final operations = [
        for (final block in body.blocks) ...[
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
      ];
      expect(operations.whereType<MaterializeValue>(), isEmpty);
      expect(
        operations.whereType<DirectCall>().where(
          (call) => call.target == heapRuntime.allocate,
        ),
        hasLength(1),
      );
      final facts = ProgramFlow(lowered, [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.integer(99))],
        ),
      ]).facts;
      expect((facts.returnedBy(target).constant as ScalarConstant).value, 8);
      expect(facts.definitions, contains(heapRuntime.allocate));
      // This controlled allocator body proves IR ordering, not native OOM handling.
    },
  );
}
