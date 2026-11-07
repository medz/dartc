import 'dart:typed_data';

import 'package:dartc/x64.dart';

import 'integer_abi.dart';

/// Emits System V integer leaf entry points used by macOS and Linux x86-64.
final class X64Abi(final Assembler assembler) implements IntegerAbi<Register> {
  @override
  List<Register> get parameters => const [.rdi, .rsi, .rdx, .rcx, .r8, .r9];

  @override
  List<Register> get temporaries => const [
    .rax,
    .rcx,
    .rdx,
    .rsi,
    .rdi,
    .r8,
    .r9,
    .r10,
    .r11,
  ];

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
  void returnValue(Register value) {
    assembler.move(.rax, value);
    assembler.ret();
  }

  @override
  Uint8List takeBytes() => assembler.takeBytes();
}
