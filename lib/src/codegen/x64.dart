import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/target.dart';
import 'package:dartc/assembler/x64.dart';

import 'function_emitter.dart';
import 'binary_encoding.dart';
import 'scalar_generator.dart';

/// Generates x86-64 scalar functions for the selected operating system.
final class X64CodeGenerator(Target target)
    extends ScalarCodeGenerator<CpuRegister> {
  this : super(target, () => _X64Emitter(Assembler(), X64Abi(target))) {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }
}

final class _X64Emitter(
  final Assembler assembler,
  @override final X64Abi convention,
) implements FunctionEmitter<CpuRegister> {
  @override
  List<CpuRegister> get allocatableRegisters => [
    ...const <Register>[.rax, .rcx, .rdx, .rsi, .rdi, .r8, .r9, .r10, .r11],
    ...FloatRegister.values,
  ];

  @override
  RegisterBank bank(CpuRegister register) =>
      register is FloatRegister ? .floating : .general;

  @override
  void move(CpuRegister destination, CpuRegister source) {
    switch ((destination, source)) {
      case (final Register d, final Register s):
        assembler.move(d, s);
      case (final FloatRegister d, final FloatRegister s):
        assembler.moveDouble(d, s);
      case (final Register d, final FloatRegister s):
        assembler.moveBitsToGeneral(d, s);
      case (final FloatRegister d, final Register s):
        assembler.moveBitsToDouble(d, s);
    }
  }

  @override
  void prologue(FrameLayout<CpuRegister> frame) =>
      convention.emitPrologue(assembler, frame);

  @override
  void epilogue(FrameLayout<CpuRegister> frame) =>
      convention.emitEpilogue(assembler, frame);

  @override
  void ret() => assembler.ret();

  @override
  Label label() => assembler.label();

  @override
  void bind(Label label) => assembler.bind(label);

  @override
  void loadImmediate(CpuRegister destination, int value) =>
      assembler.loadImmediate(destination as Register, value);

  @override
  BinaryEncoding<CpuRegister> get add => _binary(assembler.add);

  @override
  BinaryEncoding<CpuRegister> get subtract => _binary(assembler.subtract);

  @override
  BinaryEncoding<CpuRegister> get multiply => _binary(assembler.multiply);

  @override
  BinaryEncoding<CpuRegister> get bitAnd => _binary(assembler.bitAnd);

  @override
  BinaryEncoding<CpuRegister> get bitOr => _binary(assembler.bitOr);

  @override
  BinaryEncoding<CpuRegister> get bitXor => _binary(assembler.bitXor);

  BinaryEncoding<CpuRegister> _binary<T extends CpuRegister>(
    void Function(T, T) emit,
  ) => .new(
    (destination, _, right) => emit(destination as T, right as T),
    reuseLeft: true,
  );

  @override
  BinaryEncoding<CpuRegister> get addDouble => _binary(assembler.addDouble);

  @override
  BinaryEncoding<CpuRegister> get subtractDouble =>
      _binary(assembler.subtractDouble);

  @override
  BinaryEncoding<CpuRegister> get multiplyDouble =>
      _binary(assembler.multiplyDouble);

  @override
  BinaryEncoding<CpuRegister> get divideDouble =>
      _binary(assembler.divideDouble);

  @override
  BinaryEncoding<CpuRegister> comparison(
    Comparison comparison, {
    bool floating = false,
  }) {
    if (floating) return _floatingComparison(comparison);
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => .lessThan,
      .lessOrEqual => .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      assembler.compare(left as Register, right as Register);
      assembler.setCondition(destination as Register, condition);
    });
  }

  @override
  bool get negationNeedsTemporary => true;

  @override
  void negateDouble(
    CpuRegister destination,
    CpuRegister source,
    CpuRegister? temporary,
  ) {
    final scratch = temporary as Register;
    assembler
      ..moveBitsToGeneral(scratch, source as FloatRegister)
      ..complementBit(scratch, 63)
      ..moveBitsToDouble(destination as FloatRegister, scratch);
  }

  BinaryEncoding<CpuRegister> _floatingComparison(Comparison comparison) =>
      .new((d, l, r) {
        final destination = d as Register,
            left = l as FloatRegister,
            right = r as FloatRegister;
        final reversed = comparison == .lessThan || comparison == .lessOrEqual;
        assembler.compareDouble(
          reversed ? right : left,
          reversed ? left : right,
        );
        if (comparison == .equal || comparison == .notEqual) {
          final unordered = assembler.label(), done = assembler.label();
          assembler.jumpCondition(.parity, unordered);
          assembler.setCondition(
            destination,
            comparison == .equal ? .equal : .notEqual,
          );
          assembler.jump(done);
          assembler.bind(unordered);
          assembler.loadImmediate(destination, comparison == .notEqual ? 1 : 0);
          assembler.bind(done);
        } else {
          assembler.setCondition(
            destination,
            comparison == .lessOrEqual || comparison == .greaterOrEqual
                ? .aboveOrEqual
                : .above,
          );
        }
      });

  @override
  void jump(Label target) => assembler.jump(target);

  @override
  void jumpIfZero(CpuRegister value, Label target) {
    assembler.test(value as Register);
    assembler.jumpCondition(.equal, target);
  }

  @override
  void loadStack(CpuRegister destination, int offset) => switch (destination) {
    Register() => assembler.load(destination, .rsp, offset),
    FloatRegister() => assembler.loadDouble(destination, .rsp, offset),
  };

  @override
  void storeStack(CpuRegister source, int offset) => switch (source) {
    Register() => assembler.store(source, .rsp, offset),
    FloatRegister() => assembler.storeDouble(source, .rsp, offset),
  };

  @override
  Fixup call() => assembler.call();

  @override
  void loadMemory(CpuRegister destination, CpuRegister base) =>
      assembler.load(destination as Register, base as Register, 0);

  @override
  void storeMemory(CpuRegister source, CpuRegister base) =>
      assembler.store(source as Register, base as Register, 0);

  @override
  Uint8List finish() => assembler.finish();
}
