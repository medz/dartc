import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/indirect_invocation.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'adapter conversion is explicit when caller and source carriers differ',
    () {
      final source = FunctionTarget(null, 'wordSource', .integer, [.integer]);
      final sourceBlock = Block(source.parameterTypes)
        ..finish(Return(const Constant.integer(42)));
      final root = FunctionTarget(null, 'refCaller', .integer, [.integer]);
      final block = Block(root.parameterTypes);
      final call = block.emit(
        FunctionCall(FunctionConstant(source), block.parameters),
      );
      block.finish(Return(call));
      final original = IrProgram(
        [],
        [
          IrFunction(source, [sourceBlock]),
          IrFunction(root, [
            block,
          ], execution: FunctionExecution({call: ExecutionShape.reference})),
        ],
        executionShapes: ExecutionShapes(
          entries: {
            root: ExecutionSignature([
              ExecutionShape.reference,
            ], ExecutionShape.reference),
          },
        ),
      );
      final lowered = CallableLowering(CallableImplementations())
          .run(ProgramFlow(original, const [], openEntries: [root]).facts);
      final program = RepresentationLowering().lower(
        lowered,
        lowered.functions.map((f) => f.target),
      );
      final body = program.implementationOf(root) as IrFunction;
      final bound = body.entry.instructions
          .whereType<FunctionCall>()
          .single
          .entryBinding!;
      final adapter =
          program.implementationOf(bound.entries[source]!) as IrFunction;
      final ops = adapter.blocks.expand((b) => b.instructions).toList();
      final projection = ops.whereType<ProjectValue>().single;
      final invocation = ops.whereType<DirectCall>().single;
      final materialization = ops.whereType<MaterializeValue>().single;
      expect(invocation.inputs.single, same(projection));
      expect(materialization.value, same(invocation));
      expect(
        materialization.effects,
        containsAll([Effect.allocates, Effect.mayThrow]),
      );
      expect(ops.indexOf(projection), lessThan(ops.indexOf(invocation)));
      expect(ops.indexOf(invocation), lessThan(ops.indexOf(materialization)));
      program.executionShapes!.verify(adapter);
    },
  );

  test(
    'two actual entries preserve reference-carried int arguments and results',
    () {
      final uri = Uri.parse('memory:call-entry-execution');
      final state = GlobalVariable(uri, 'state', .integer, isLate: true);
      final sources = [
        FunctionTarget(uri, 'left', .integer, [.integer]),
        FunctionTarget(uri, 'right', .integer, [.integer]),
      ];
      final bodies = [
        for (final (i, target) in sources.indexed)
          () {
            final block = Block(target.parameterTypes);
            block.emit(StoreGlobal(state, Constant.integer(i == 0 ? 9 : 73)));
            block.finish(
              Return(
                i == 0 ? block.parameters.single : const Constant.integer(43),
              ),
            );
            return IrFunction(target, [block]);
          }(),
      ];
      final root = FunctionTarget(uri, 'choose', .integer, [
        .boolean,
        .integer,
      ]);
      final entry = Block(root.parameterTypes),
          left = Block(),
          right = Block(),
          join = Block([sources.first.signature]);
      entry.finish(Branch(entry.parameters.first, Jump(left), Jump(right)));
      left.finish(Jump(join, [FunctionConstant(sources.first)]));
      right.finish(Jump(join, [FunctionConstant(sources.last)]));
      final call = join.emit(
        FunctionCall(join.parameters.single, [entry.parameters.last]),
      );
      join.emit(KeepAlive(entry.parameters.last));
      join.finish(Return(call));
      final rootBody = IrFunction(root, [
        entry,
        left,
        right,
        join,
      ], execution: FunctionExecution({call: ExecutionShape.reference}));
      final read = FunctionTarget(uri, 'stateValue', .integer, []);
      final readBlock = Block();
      readBlock.finish(Return(readBlock.emit(LoadGlobal(state))));
      final original = IrProgram(
        [],
        [
          ...bodies,
          rootBody,
          IrFunction(read, [readBlock]),
        ],
        globals: [state],
        executionShapes: ExecutionShapes(
          entries: {
            root: ExecutionSignature([
              ExecutionShape.word,
              ExecutionShape.reference,
            ], ExecutionShape.reference),
            for (final source in sources)
              source: ExecutionSignature([
                ExecutionShape.reference,
              ], ExecutionShape.reference),
          },
        ),
      );
      final owner = CallableImplementations();
      var program = CallableLowering(owner)
          .run(ProgramFlow(original, const [], openEntries: [root]).facts);
      program = RepresentationLowering().lower(
        program,
        program.functions.map((f) => f.target),
      );
      final body = program.implementationOf(root) as IrFunction;
      final boundCall = body.blocks
          .expand((b) => b.instructions)
          .whereType<FunctionCall>()
          .single;
      final binding = boundCall.entryBinding!;
      expect(binding.entries.keys.toSet(), sources.toSet());
      expect(binding.shape.positional, [ValueType.integer]);
      expect(binding.shape.execution.parameters, [
        ExecutionShape.reference,
        ExecutionShape.reference,
      ]);
      expect(binding.shape.execution.result, ExecutionShape.reference);
      for (final adapter in binding.entries.values) {
        expect(
          program.executionShapes!.entryOf(adapter),
          binding.shape.execution,
        );
        program.executionShapes!.verify(
          program.implementationOf(adapter) as IrFunction,
        );
      }
      for (final choice in [true, false]) {
        final runner = IrInterpreter(program, {});
        expect(runner.run(body, [choice, 42]), choice ? 42 : 43);
        expect(
          runner.run(program.implementationOf(read) as IrFunction, []),
          choice ? 9 : 73,
        );
      }
      final rebound = CallableLowering(CallableImplementations())
          .run(ProgramFlow(program, const [], openEntries: [root]).facts);
      expect(rebound, same(program));
      expect(
        () => IrProgram(
          program.classes,
          program.functions,
          globals: program.globals,
        ),
        throwsArgumentError,
      );

      final facts = ProgramFlow(program, const [], openEntries: [root]).facts;
      final storage = ClosureStorage(
        program.functions,
        storageDeclarations: program.classes,
        callableImplementations: owner,
      );
      final layouts = ProgramLayout(
        [...program.classes, ...storage.classes],
        closureStorage: storage,
        executionShapes: program.executionShapes!,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final selected = FunctionRepresentation(
        body,
        layouts,
        CheckedCasts(),
        MemberCalls(program, facts.definitions, callTypes: facts),
        HeapPlan(),
      );
      final indirect = selected.instructions.values
          .expand((ops) => ops)
          .whereType<IndirectInvocation>()
          .single;
      expect(indirect.execution, binding.shape.execution);
      expect(selected.shapeOf(indirect), ExecutionShape.reference);
      final selection = FunctionSelection(selected, _Constraints());
      expect(
        selection.calls[indirect]!.parameterShapes,
        binding.shape.execution.parameters,
      );
      final allocation = FunctionAllocation(selection);
      final input = selected.entryParameters.last;
      expect(selection.liveReferences[indirect], contains(input));
      expect(
        allocation.safepoints[indirect]!.offsets,
        contains(allocation.homes[input]!.offset),
      );
    },
  );
}

final class _Constraints() implements FunctionEmitter<CpuRegister> {
  @override
  final convention = Arm64Abi(const Target(.linux, .arm64));
  @override
  final allocatableRegisters = <CpuRegister>[
    Register.x0,
    Register.x1,
    Register.x2,
    Register.x3,
    FloatRegister.d0,
    FloatRegister.d1,
    FloatRegister.d2,
    FloatRegister.d3,
  ];
  @override
  RegisterBank bank(CpuRegister register) =>
      register is Register ? .general : .floating;
  @override
  CpuRegister get exceptionRegister => Register.x0;
  @override
  CpuRegister get traceRegister => Register.x1;
  @override
  CpuRegister get failureRegister => Register.x16;
  @override
  bool get negationNeedsTemporary => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
