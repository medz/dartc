import 'dart:typed_data';

import 'package:dartc/arm64.dart';

import 'integer_abi.dart';

/// Emits integer leaf entry points shared by macOS and Linux AArch64.
final class Arm64Abi(final Assembler assembler)
    implements IntegerAbi<Register> {
  @override
  List<Register> get parameters => const [
    .x0,
    .x1,
    .x2,
    .x3,
    .x4,
    .x5,
    .x6,
    .x7,
  ];

  @override
  List<Register> get temporaries => const [
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
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  void add(Register destination, Register left, Register right) =>
      assembler.add(destination, left, right);

  @override
  void subtract(Register destination, Register left, Register right) =>
      assembler.subtract(destination, left, right);

  @override
  void returnValue(Register value) {
    assembler.move(.x0, value);
    assembler.ret();
  }

  @override
  Uint8List takeBytes() => assembler.takeBytes();
}
