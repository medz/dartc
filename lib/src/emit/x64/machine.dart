import 'package:dartc/lir.dart';

import '../allocate.dart';
import '../machine.dart';
import 'assembler.dart';
import 'operations.dart';
import 'registers.dart';

const _rax = X64Assembler.rax, _rsp = X64Assembler.rsp;
const _rbp = X64Assembler.rbp;

/// What x64 processors do for functions, some of which are [_externals].
final class X64Machine(
  final X64Assembler _assembler,
  final Set<String> _externals,
) implements Machine {
  late final _operations = X64Operations(_assembler);

  @override
  MachineRegisters get registers => x64Registers;

  @override
  int get offset => _assembler.offset;

  @override
  void enter(
    int bytes, {
    required bool checksStack,
    required void Function() onCheck,
  }) {
    _assembler
      ..push(_rbp)
      ..mov(_rbp, _rsp);
    if (checksStack) {
      final enough = Label();
      _assembler
        ..lea(rightScratch, Memory(_rbp, offset: -bytes))
        ..cmpSymbol(rightScratch, stackLimitSymbol)
        ..jumpIf(.aboveOrEqual, enough)
        ..call(stackOverflowSymbol);
      onCheck();
      _assembler
        ..breakpoint()
        ..bind(enough);
    }
    if (bytes > 0) _assembler.subStack(bytes);
  }

  @override
  void leave() => _assembler
    ..leave()
    ..ret();

  @override
  void restoreStack(int bytes) =>
      _assembler.lea(_rsp, Memory(_rbp, offset: -bytes));

  @override
  void copy(InRegister from, InRegister to) => from.bank == .word
      ? _assembler.mov(to.number, from.number)
      : _assembler.fmov(to.number, from.number);

  @override
  void constant(int register, int value) =>
      _assembler.constant(register, value);

  @override
  bool takesImmediate(IntOp op, int value) => switch (op) {
    .add ||
    .sub ||
    .mul ||
    .and ||
    .or ||
    .xor => X64Assembler.isImmediate(value) && X64Assembler.isImmediate(-value),
    .shl || .sar || .shr => value >= 0 && value < 64,
    .div || .rem => false,
  };

  @override
  bool comparesImmediate(int value) => X64Assembler.isImmediate(value);

  @override
  void access(
    InRegister register,
    int offset, {
    required bool fromFrame,
    required bool store,
  }) {
    final at = Memory(fromFrame ? _rbp : _rsp, offset: offset);
    final float = register.bank == .float;
    store
        ? _assembler.store(register.number, at, float: float)
        : _assembler.load(register.number, at, float: float);
  }

  @override
  void accessAll(
    List<InRegister> registers,
    int offset, {
    required bool store,
  }) {
    for (final (i, register) in registers.indexed) {
      access(register, offset + i * 8, fromFrame: false, store: store);
    }
  }

  @override
  void call(String symbol, LirSignature signature) {
    // Functions with variable arguments are told how many are doubles.
    if (_externals.contains(symbol)) {
      final floats = signature.parameters.where((type) => type == .f64).length;
      _assembler.constant(_rax, floats);
    }
    _assembler.call(symbol);
  }

  @override
  void callRegister(int register) => _assembler.unary(.call, register);

  @override
  void resume() => _assembler
    ..mov(_rbp, x64Registers.resumedFrame)
    ..unary(.jmp, x64Registers.callee);

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
  }) => _assembler
    ..binary(.test, register, register)
    ..jumpIf(isZero ? .equal : .notEqual, label);

  @override
  void jumpIf(
    Compare comparison,
    List<int> operands,
    covariant Label label, {
    required bool holds,
    int? immediate,
  }) => _operations.jumpIf(
    comparison,
    operands,
    label,
    holds: holds,
    immediate: immediate,
  );

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
    Compare(left: LirValue(type: .i64), :final relation)
        when immediate != null =>
      _operations.setComparison(relation, result, operands.single, immediate),
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
