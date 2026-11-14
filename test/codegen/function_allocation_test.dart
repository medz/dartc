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
  SelectedFunction select(FunctionTarget target, List<Block> blocks) {
    final body = SelectedFunction(target, ProgramLayout([]), blocks.first);
    for (final block in blocks) {
      body.blocks.add(block);
      body.instructions[block] = block.instructions.toList();
      body.ends[block] = block.end;
    }
    return body;
  }

  test('matching block-entry registers require no edge loads or stores', () {
    final target = FunctionTarget(uri, 'forward', .integer, [
      .integer,
      .integer,
      .integer,
    ]);
    final entry = Block(target.parameterTypes);
    final next = Block(target.parameterTypes);
    final edge = Jump(next, entry.parameters);
    entry.finish(edge);
    next.emit(KeepAlive(next.parameters[1]));
    next.emit(KeepAlive(next.parameters[2]));
    next.finish(Return(next.parameters.first));
    final emitter = _Emitter()
      ..registers[Register.x0] = 11
      ..registers[Register.x1] = 22
      ..registers[Register.x2] = 33;
    final selection = FunctionSelection(select(target, [entry, next]), emitter);
    final allocation = FunctionAllocation(emitter, selection, (_, _) {});
    allocation.begin(entry);
    allocation.prepareEdges(entry);
    allocation.copyArguments(edge);
    allocation.begin(next);
    expect(
      [
        for (final value in next.parameters)
          emitter.registers[allocation.read(value)],
      ],
      [11, 22, 33],
    );
    expect(emitter.position, 0);
  });

  test(
    'critical loop edges preserve register and stack parameter rotations',
    () {
      for (final reverse in [false, true]) {
        final target = FunctionTarget(
          uri,
          'rotate',
          .integer,
          List.filled(4, ValueType.integer),
        );
        final entry = Block(target.parameterTypes);
        final loop = Block(target.parameterTypes);
        final entryEdge = Jump(loop, entry.parameters);
        entry.finish(entryEdge);
        final rotate = Jump(loop, [
          ...loop.parameters.skip(1),
          loop.parameters.first,
        ]);
        final backwards = Jump(loop, loop.parameters.reversed);
        for (final value in loop.parameters) {
          loop.emit(KeepAlive(value));
        }
        loop.finish(Branch(const Constant.boolean(true), rotate, backwards));
        final emitter = _Emitter()
          ..registers[Register.x0] = 11
          ..registers[Register.x1] = 22
          ..registers[Register.x2] = 33
          ..registers[Register.x3] = 44;
        final selection = FunctionSelection(
          select(target, [entry, loop]),
          emitter,
        );
        final allocation = FunctionAllocation(emitter, selection, (_, _) {});
        allocation.begin(entry);
        allocation.prepareEdges(entry);
        allocation.copyArguments(entryEdge);
        var expected = [11, 22, 33, 44];
        for (var i = 0; i < 7; i++) {
          allocation.begin(loop);
          expect([
            for (final value in loop.parameters)
              emitter.registers[allocation.read(value)],
          ], expected);
          allocation.prepareEdges(loop);
          allocation.copyArguments(reverse ? backwards : rotate);
          expected = reverse
              ? expected.reversed.toList()
              : [...expected.skip(1), expected.first];
        }
      }
    },
  );

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
      final body = select(target, [block])..invocations[call] = callee;
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
      final selection = FunctionSelection(select(target, [block]), emitter);
      final allocation = FunctionAllocation(emitter, selection, (_, _) {});
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
