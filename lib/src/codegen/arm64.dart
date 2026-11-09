import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/target.dart';

import 'function_emitter.dart';
import 'binary_encoding.dart';
import 'scalar_generator.dart';

/// Generates AArch64 scalar functions for the selected operating system.
final class Arm64CodeGenerator(Target target)
    extends ScalarCodeGenerator<CpuRegister> {
  this : super(target, () => _Arm64Emitter(Assembler(), Arm64Abi(target))) {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }
}

final class _Arm64Emitter(
  final Assembler assembler,
  @override final Arm64Abi convention,
) implements FunctionEmitter<CpuRegister> {
  @override
  List<CpuRegister> get allocatableRegisters => [
    ...const <Register>[
      .x0,
      .x1,
      .x2,
      .x3,
      .x4,
      .x5,
      .x6,
      .x7,
      .x9,
      .x10,
      .x11,
      .x12,
      .x13,
      .x14,
      .x15,
    ],
    ...FloatRegister.values.take(8),
    ...FloatRegister.values.skip(16),
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
    void Function(T, T, T) emit,
  ) => .new((d, l, r) => emit(d as T, l as T, r as T));

  @override
  bool get negationNeedsTemporary => false;

  @override
  void negateDouble(
    CpuRegister destination,
    CpuRegister source,
    CpuRegister? temporary,
  ) => assembler.negateDouble(
    destination as FloatRegister,
    source as FloatRegister,
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
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => floating ? .negative : .lessThan,
      .lessOrEqual => floating ? .lowerOrEqual : .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      if (floating) {
        assembler.compareDouble(left as FloatRegister, right as FloatRegister);
      } else {
        assembler.compare(left as Register, right as Register);
      }
      assembler.setCondition(destination as Register, condition);
    });
  }

  @override
  void jump(Label target) => assembler.branch(target);

  @override
  void jumpIfZero(CpuRegister value, Label target) =>
      assembler.branchZero(value as Register, target);

  @override
  void loadStack(CpuRegister destination, int offset) => switch (destination) {
    Register() => assembler.load(destination, .sp, offset),
    FloatRegister() => assembler.loadDouble(destination, .sp, offset),
  };

  @override
  void storeStack(CpuRegister source, int offset) => switch (source) {
    Register() => assembler.store(source, .sp, offset),
    FloatRegister() => assembler.storeDouble(source, .sp, offset),
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
