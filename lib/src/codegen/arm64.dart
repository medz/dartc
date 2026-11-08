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
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  void add(Register destination, Register left, Register right) =>
      assembler.add(destination, left, right);

  @override
  void subtract(Register destination, Register left, Register right) =>
      assembler.subtract(destination, left, right);

  @override
  Uint8List takeBytes() => assembler.takeBytes();
}
