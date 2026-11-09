import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/arm64.dart';
import 'package:dartc/target.dart';

import 'function_emitter.dart';
import 'integer_generator.dart';

/// Generates AArch64 integer functions for the selected operating system.
final class Arm64CodeGenerator(Target target)
    extends IntegerCodeGenerator<Register> {
  this : super(target, () => _Arm64Emitter(Assembler())) {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }
}

final class _Arm64Emitter(final Assembler assembler)
    implements FunctionEmitter<Register> {
  @override
  final CallingConvention<Register> convention = Arm64Abi(assembler);

  @override
  int get position => assembler.length;

  @override
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  void add(Register destination, Register left, Register right) =>
      assembler.add(destination, left, right);

  @override
  void subtract(Register destination, Register left, Register right) =>
      assembler.subtract(destination, left, right);

  @override
  void compare(
    Register destination,
    Register left,
    Register right,
    Comparison comparison,
  ) {
    assembler.compare(left, right);
    assembler.setCondition(destination, switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => .lessThan,
      .lessOrEqual => .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    });
  }

  @override
  int jump() {
    final offset = assembler.length;
    assembler.branch(0);
    return offset;
  }

  @override
  int jumpIfZero(Register value) {
    final offset = assembler.length;
    assembler.branchZero(value, 0);
    return offset;
  }

  @override
  void patchJump(ByteData code, int offset, int destination) =>
      code.patchArm64Branch(offset, destination - offset);

  @override
  void loadStack(Register destination, int offset) =>
      assembler.load(destination, .sp, offset);

  @override
  void storeStack(Register source, int offset) =>
      assembler.store(source, .sp, offset);

  @override
  int call() {
    final offset = assembler.length;
    assembler.call(0);
    return offset;
  }

  @override
  Uint8List takeBytes() => assembler.takeBytes();
}
