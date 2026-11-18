import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:execution-shapes');
  final collect = FunctionTarget(uri, 'collect', .voidType, []);

  SelectedFunction select(IrFunction function, ExecutionShapes shapes) {
    final body = SelectedFunction(
      function.target,
      ProgramLayout(
        [],
        executionShapes: shapes,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      ),
      function.entry,
      sourceFunction: function,
    );
    for (final block in function.blocks) {
      body.blocks.add(block);
      body.instructions[block] = [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ];
      body.ends[block] = block.end;
      for (final operation in body.instructions[block]!) {
        if (operation case DirectCall(:final target)) {
          body.invocations[operation] = target;
        }
      }
    }
    return body;
  }

  test('a scalar language value with reference storage is a live GC root', () {
    final target = FunctionTarget(uri, 'retain', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final value = entry.parameters.single;
    final call = entry.emit(DirectCall(collect, []));
    entry.finish(Return(value));
    final source = IrFunction(target, [entry]);
    final shapes = ExecutionShapes(
      entries: {
        target: ExecutionSignature([
          ExecutionShape.reference,
        ], ExecutionShape.reference),
      },
    );
    final body = select(source, shapes);
    final selection = FunctionSelection(body, _Constraints());
    final allocation = FunctionAllocation(selection);
    expect(value.type, ValueType.integer);
    expect(body.shapeOf(value), ExecutionShape.reference);
    expect(selection.liveReferences[call], {value});
    expect(
      allocation.safepoints[call]!.offsets,
      contains(allocation.homes[value]!.offset),
    );
  });

  test('raw scalar words across the same call are not traced', () {
    final target = FunctionTarget(uri, 'retainWord', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final call = entry.emit(DirectCall(collect, []));
    entry.finish(Return(entry.parameters.single));
    final body = select(IrFunction(target, [entry]), ExecutionShapes.defaults);
    final selection = FunctionSelection(body, _Constraints());
    final allocation = FunctionAllocation(selection);
    expect(selection.liveReferences[call], isEmpty);
    expect(allocation.safepoints[call]!.offsets, isEmpty);
  });

  test('explicit payload reads keep their scalar typed backing rooted', () {
    final target = FunctionTarget(uri, 'project', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final value = entry.parameters.single;
    final call = entry.emit(DirectCall(collect, []));
    final payload = entry.emit(
      LoadObjectData(
        value,
        const Constant.integer(ObjectHeader.fieldsOffset),
        NativeScalarType(Int64),
      ),
    );
    entry.finish(Return(payload));
    final shapes = ExecutionShapes(
      entries: {
        target: ExecutionSignature([
          ExecutionShape.reference,
        ], ExecutionShape.word),
      },
    );
    final body = select(IrFunction(target, [entry]), shapes);
    final selection = FunctionSelection(body, _Constraints());
    final allocation = FunctionAllocation(selection);
    expect(selection.liveReferences[call], {value});
    expect(body.shapeOf(payload), ExecutionShape.word);
    expect(allocation.operations[payload]!.inputs, hasLength(2));
  });

  test('a semantic scalar alone is not a managed memory capability', () {
    final target = FunctionTarget(uri, 'invalidPayloadRead', .integer, [
      .integer,
    ]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          LoadObjectData(
            entry.parameters.single,
            const Constant.integer(ObjectHeader.fieldsOffset),
            NativeScalarType(Int64),
          ),
        ),
      ),
    );
    final body = select(IrFunction(target, [entry]), ExecutionShapes.defaults);
    expect(() => FunctionSelection(body, _Constraints()), throwsStateError);
  });

  test('callee results and caller storage use the same explicit signature', () {
    final callee = FunctionTarget(uri, 'scalarThroughReference', .integer, [
      .integer,
    ]);
    final target = FunctionTarget(uri, 'caller', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final call = entry.emit(DirectCall(callee, entry.parameters));
    final poll = entry.emit(DirectCall(collect, []));
    entry.finish(Return(call));
    final signature = ExecutionSignature([
      ExecutionShape.reference,
    ], ExecutionShape.reference);
    final shapes = ExecutionShapes(
      entries: {target: signature, callee: signature},
    );
    final body = select(IrFunction(target, [entry]), shapes);
    final selected = FunctionSelection(body, _Constraints());
    final allocated = FunctionAllocation(selected);
    expect(body.shapeOf(call), ExecutionShape.reference);
    expect(selected.calls[call]!.parameterShapes, [ExecutionShape.reference]);
    expect(selected.liveReferences[poll], {call});
    expect(
      allocated.safepoints[poll]!.offsets,
      contains(allocated.homes[call]!.offset),
    );
  });

  test('a pure type view cannot silently materialize a scalar result', () {
    final target = FunctionTarget(uri, 'unlowered', .object, [.integer]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(entry.emit(TypeView(entry.parameters.single, .object))),
    );
    final body = select(IrFunction(target, [entry]), ExecutionShapes.defaults);
    expect(() => FunctionSelection(body, _Constraints()), throwsStateError);
  });

  test(
    'physical slot choices drive both field layout and reference bitmap',
    () {
      final owner = ClassType(uri, 'Storage');
      final field = InstanceField(owner, 'value', .integer, isFinal: true);
      final layout = ProgramLayout(
        [
          IrClass(owner, [field]),
        ],
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        executionShapes: ExecutionShapes(
          slots: {field: ExecutionShape.reference},
        ),
      );
      expect(layout.storageOf(owner).layout.fields, [
        ValueRepresentation.reference,
      ]);
      expect(
        layout.storageOf(owner).layout.referenceOffsets,
        contains(layout.fieldOffset(field)),
      );
      final data = ConstantData(layout, 0);
      final symbol = data.addressOf(
        ObjectConstant(owner, {field: const Constant.integer(73)}),
      );
      final fieldOffset =
          data.symbols[symbol].offset + layout.fieldOffset(field);
      expect(
        data.relocations.where(
          (relocation) => relocation.offset == fieldOffset,
        ),
        hasLength(1),
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
