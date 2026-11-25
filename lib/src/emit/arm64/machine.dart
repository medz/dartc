import 'package:dartc/lir.dart';

import '../allocate.dart';
import '../machine.dart';
import 'assembler.dart';
import 'operations.dart';
import 'registers.dart';

const _frame = Arm64Assembler.frame, _stack = Arm64Assembler.stack;

/// What ARM64 processors do for functions.
final class Arm64Machine(final Arm64Assembler _assembler) implements Machine {
  late final _operations = Arm64Operations(_assembler);

  @override
  MachineRegisters get registers => arm64Registers;

  @override
  int get offset => _assembler.offset;

  @override
  void enter(
    int bytes, {
    required bool checksStack,
    required void Function() onCheck,
  }) {
    _assembler
      ..pushFrame()
      ..addImmediate(_frame, _stack, 0);
    if (checksStack) _checkStack(bytes, onCheck);
    if (bytes > 0) {
      _assembler
        ..constant(rightScratch, bytes)
        ..subStack(rightScratch);
    }
  }

  void _checkStack(int bytes, void Function() onCheck) {
    final enough = Label();
    var lowest = _frame;
    // There is more below the limit than little frames take.
    if (bytes > littleFrame) {
      _assembler
        ..constant(rightScratch, bytes)
        ..sub(rightScratch, _frame, rightScratch);
      lowest = rightScratch;
    }
    _assembler
      ..address(farScratch, stackLimitSymbol)
      ..load(farScratch, farScratch, 0)
      ..cmp(lowest, farScratch)
      ..jumpIf(.lo, enough, holds: false)
      ..call(stackOverflowSymbol);
    onCheck();
    _assembler
      ..breakpoint()
      ..bind(enough);
  }

  @override
  void leave() => _assembler
    ..addImmediate(_stack, _frame, 0)
    ..popFrame()
    ..ret();

  @override
  void restoreStack(int bytes) => _assembler
    ..constant(rightScratch, bytes)
    ..sub(rightScratch, _frame, rightScratch)
    ..addImmediate(_stack, rightScratch, 0);

  @override
  void copy(InRegister from, InRegister to) => from.bank == .word
      ? _assembler.mov(to.number, from.number)
      : _assembler.fmov(to.number, from.number);

  @override
  void constant(int register, int value) =>
      _assembler.constant(register, value);

  @override
  bool takesImmediate(IntOp op, int value) => switch (op) {
    .add || .sub => Arm64Assembler.isAddable(value),
    .mul => value > 0 && value & (value - 1) == 0,
    .and || .or || .xor => Arm64Assembler.maskOf(value) != null,
    .shl || .sar || .shr => value >= 0 && value < 64,
    .div || .rem => false,
  };

  @override
  bool comparesImmediate(int value) => Arm64Assembler.isSmall(value);

  @override
  void access(
    InRegister register,
    int offset, {
    required bool fromFrame,
    required bool store,
  }) {
    final base = fromFrame ? _frame : _stack;
    final number = register.number, float = register.bank == .float;
    if (offset <= Arm64Assembler.maxOffset) {
      store
          ? _assembler.store(number, base, offset, float: float)
          : _assembler.load(number, base, offset, float: float);
      return;
    }
    _assembler.constant(farScratch, offset);
    store
        ? _assembler.storeIndexed(number, base, farScratch, float: float)
        : _assembler.loadIndexed(number, base, farScratch, float: float);
  }

  @override
  void accessAll(
    List<InRegister> registers,
    int offset, {
    required bool store,
  }) {
    for (var i = 0; i < registers.length; i++) {
      final InRegister(:bank, :number) = registers[i];
      final at = offset + i * 8;
      final next = registers.elementAtOrNull(i + 1);
      if (next?.bank != bank || !Arm64Assembler.pairReaches(at)) {
        access(registers[i], at, fromFrame: false, store: store);
        continue;
      }
      final other = next!.number, float = bank == .float;
      store
          ? _assembler.storePair(number, other, _stack, at, float: float)
          : _assembler.loadPair(number, other, _stack, at, float: float);
      i++;
    }
  }

  @override
  void call(String symbol, LirSignature signature) => _assembler.call(symbol);

  @override
  void callRegister(int register) => _assembler.callRegister(register);

  @override
  void resume() => _assembler
    ..mov(_frame, arm64Registers.resumedFrame)
    ..jumpRegister(arm64Registers.callee);

  @override
  Label label() => Label();

  @override
  void bind(covariant Label label) => _assembler.bind(label);

  @override
  void jump(covariant Label label) => _assembler.jump(label);

  @override
  void jumpIfZero(
    int register,
    covariant Label label, {
    required bool isZero,
  }) => _assembler.jumpIfZero(register, label, isZero: isZero);

  @override
  void jumpIf(
    Compare comparison,
    List<int> operands,
    covariant Label label, {
    required bool holds,
    int? immediate,
  }) {
    final condition = _operations.compare(comparison, operands, immediate);
    _assembler.jumpIf(condition, label, holds: holds);
  }

  @override
  void breakpoint() => _assembler.breakpoint();

  @override
  void operation(
    LirInstruction instruction,
    int result,
    List<int> operands, {
    int? immediate,
    bool isScaled = false,
  }) => switch (instruction) {
    IntBinary(:final op) when immediate != null => _operations.immediate(
      op,
      result,
      operands.single,
      immediate,
    ),
    Compare() => _operations.setComparison(
      instruction,
      result,
      operands,
      immediate,
    ),
    _ => _operations.emit(instruction, result, operands, isScaled: isScaled),
  };

  @override
  void store(
    Store store,
    int base,
    int? index,
    int value, {
    bool isScaled = false,
  }) => _operations.store(store, base, index, value, isScaled: isScaled);
}
