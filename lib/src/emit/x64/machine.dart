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
  void jumpIfZero(int register, covariant Label label) => _assembler
    ..binary(.test, register, register)
    ..jumpIf(.equal, label);

  @override
  void breakpoint() => _assembler.breakpoint();

  @override
  void operation(LirInstruction instruction, int result, List<int> operands) =>
      _operations.emit(instruction, result, operands);

  @override
  void store(Store store, int base, int? index, int value) =>
      _operations.store(store, base, index, value);
}
