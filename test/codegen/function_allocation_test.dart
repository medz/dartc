import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/binary_encoding.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:allocation');
  SelectedFunction select(FunctionTarget target, Block block) =>
      SelectedFunction(target, ProgramLayout([]), block)
        ..blocks.add(block)
        ..instructions[block] = block.instructions.toList()
        ..ends[block] = block.end;

  test(
    'preassigned roots exclude consumed arguments and reload relocated homes',
    () {
      final target = FunctionTarget(uri, 'caller', .object, [
        .object,
        .integer,
        .object,
        ...List.filled(5, ValueType.integer),
        .object,
      ]);
      final block = Block(target.parameterTypes);
      final callee = FunctionTarget(uri, 'collect', .voidType, [.object]);
      final call = block.emit(DirectCall(callee, [block.parameters[2]]));
      block.emit(KeepAlive(block.parameters[0]));
      block.emit(KeepAlive(block.parameters[1]));
      block.finish(Return(block.parameters[8]));
      final body = select(target, block)..invocations[call] = callee;
      final emitter = _Emitter()
        ..registers[Register.x0] = 0x100
        ..registers[Register.x1] = 0x200
        ..registers[Register.x2] = 0x300;
      final selection = FunctionSelection(body, emitter);
      final allocation = FunctionAllocation(emitter, selection, (_, _) {});
      final roots = allocation.safepoints[call]!;
      expect(emitter.position, 0);
      expect(roots.offsets, hasLength(2));
      emitter.stack[allocation.frame!.incomingStackOffset] = 0x900;
      allocation.initialize();
      allocation.begin(block);
      allocation.prepareCall(call);
      expect(roots.offsets.map((offset) => emitter.stack[offset]).toSet(), {
        0x100,
        0x900,
      });
      for (final offset in roots.offsets) {
        emitter.stack[offset] = emitter.stack[offset]! + 1;
      }
      expect(emitter.registers[allocation.read(block.parameters[0])], 0x101);
      expect(emitter.registers[allocation.read(block.parameters[8])], 0x901);
      expect(emitter.registers[allocation.read(block.parameters[1])], 0x200);
    },
  );

  test(
    'fixed operands preserve swapped sources and other clobbered values',
    () {
      final target = FunctionTarget(uri, 'fixed', .integer, [
        .integer,
        .integer,
        .integer,
      ]);
      final block = Block(target.parameterTypes);
      final operation = block.emit(
        IntBinary(.subtract, block.parameters[1], block.parameters[0]),
      );
      block.emit(KeepAlive(block.parameters[2]));
      block.finish(Return(operation));
      final emitter = _Emitter()
        ..registers[Register.x0] = 3
        ..registers[Register.x1] = 20
        ..registers[Register.x2] = 99;
      final selection = FunctionSelection(select(target, block), emitter);
      final allocation = FunctionAllocation(emitter, selection, (_, _) {});
      allocation.initialize();
      allocation.begin(block);
      final operands = allocation.binaryOperands(operation);
      selection.binaries[operation]!.encoding.emit(
        operands.result,
        operands.left,
        operands.right,
      );
      allocation.finishBinary(operation, operands);
      expect(emitter.registers[allocation.read(operation)], 17);
      expect(emitter.registers[allocation.read(block.parameters[2])], 99);
    },
  );
}

final class _Emitter() implements FunctionEmitter<CpuRegister> {
  final registers = <CpuRegister, int>{};
  final stack = <int, int>{};
  @override
  int position = 0;
  @override
  final convention = Arm64Abi(const Target(.linux, .arm64));
  @override
  final allocatableRegisters = <CpuRegister>[
    Register.x0,
    Register.x1,
    Register.x2,
    Register.x3,
  ];
  @override
  RegisterBank bank(CpuRegister register) =>
      register is Register ? .general : .floating;
  @override
  void storeStack(CpuRegister register, int offset, {int bytes = 8}) {
    stack[offset] = registers[register]!;
    position++;
  }

  @override
  void loadStack(
    CpuRegister register,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) {
    registers[register] = stack[offset]!;
    position++;
  }

  @override
  void move(CpuRegister destination, CpuRegister source) {
    registers[destination] = registers[source]!;
    position++;
  }

  @override
  BinaryEncoding<CpuRegister> get subtract => BinaryEncoding(
    (destination, left, right) {
      registers[destination] = registers[left]! - registers[right]!;
      position++;
    },
    fixed: (
      left: Register.x0,
      right: Register.x1,
      result: Register.x0,
      clobbered: {Register.x2},
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
