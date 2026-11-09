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
    extends ScalarCodeGenerator<Register> {
  this : super(target, () => _Arm64Emitter(Assembler(), Arm64Abi(target))) {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }
}

final class _Arm64Emitter(
  final Assembler assembler,
  @override final Arm64Abi convention,
) implements FunctionEmitter<Register> {
  @override
  List<Register> get allocatableRegisters => const [
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
  ];

  @override
  void move(Register destination, Register source) =>
      assembler.move(destination, source);

  @override
  void prologue(FrameLayout<Register> frame) =>
      convention.emitPrologue(assembler, frame);

  @override
  void epilogue(FrameLayout<Register> frame) =>
      convention.emitEpilogue(assembler, frame);

  @override
  void ret() => assembler.ret();

  @override
  Label label() => assembler.label();

  @override
  void bind(Label label) => assembler.bind(label);

  @override
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  BinaryEncoding<Register> get add => .new(assembler.add);

  @override
  BinaryEncoding<Register> get subtract => .new(assembler.subtract);

  @override
  BinaryEncoding<Register> get multiply => .new(assembler.multiply);

  @override
  BinaryEncoding<Register> get bitAnd => .new(assembler.bitAnd);

  @override
  BinaryEncoding<Register> get bitOr => .new(assembler.bitOr);

  @override
  BinaryEncoding<Register> get bitXor => .new(assembler.bitXor);

  @override
  BinaryEncoding<Register> comparison(Comparison comparison) {
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => .lessThan,
      .lessOrEqual => .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      assembler.compare(left, right);
      assembler.setCondition(destination, condition);
    });
  }

  @override
  void jump(Label target) => assembler.branch(target);

  @override
  void jumpIfZero(Register value, Label target) =>
      assembler.branchZero(value, target);

  @override
  void loadStack(Register destination, int offset) =>
      assembler.load(destination, .sp, offset);

  @override
  void storeStack(Register source, int offset) =>
      assembler.store(source, .sp, offset);

  @override
  Fixup call() => assembler.call();

  @override
  void loadMemory(Register destination, Register base) =>
      assembler.load(destination, base, 0);

  @override
  void storeMemory(Register source, Register base) =>
      assembler.store(source, base, 0);

  @override
  Uint8List finish() => assembler.finish();
}
