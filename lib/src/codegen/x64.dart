import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart';

import 'function_emitter.dart';
import 'integer_generator.dart';

/// Generates x86-64 integer functions for the selected operating system.
final class X64CodeGenerator(Target target)
    extends IntegerCodeGenerator<Register> {
  this : super(target, () => _X64Emitter(Assembler())) {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }
}

final class _X64Emitter(final Assembler assembler)
    implements FunctionEmitter<Register> {
  @override
  final CallingConvention<Register> convention = X64Abi(assembler);

  @override
  int get position => assembler.length;

  @override
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  void add(Register destination, Register left, Register right) {
    if (destination == right) {
      assembler.add(destination, left);
    } else {
      assembler.move(destination, left);
      assembler.add(destination, right);
    }
  }

  @override
  void subtract(Register destination, Register left, Register right) {
    if (destination == right && destination != left) {
      assembler.negate(destination);
      assembler.add(destination, left);
    } else {
      assembler.move(destination, left);
      assembler.subtract(destination, right);
    }
  }

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
    final offset = assembler.length + 1;
    assembler.jump(0);
    return offset;
  }

  @override
  int jumpIfZero(Register value) {
    assembler.test(value);
    final offset = assembler.length + 2;
    assembler.jumpCondition(.equal, 0);
    return offset;
  }

  @override
  void patchJump(ByteData code, int offset, int destination) =>
      code.patchX64Branch(offset, destination - offset - 4);

  @override
  void loadStack(Register destination, int offset) =>
      assembler.loadStack(destination, offset);

  @override
  void storeStack(Register source, int offset) =>
      assembler.storeStack(source, offset);

  @override
  int call() {
    final offset = assembler.length + 1;
    assembler.call(0);
    return offset;
  }

  @override
  Uint8List takeBytes() => assembler.takeBytes();
}
