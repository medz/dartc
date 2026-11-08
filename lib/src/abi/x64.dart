import 'package:dartc/x64.dart';

import 'calling_convention.dart';

/// Emits System V integer leaf entry points used by macOS and Linux x86-64.
final class X64Abi(final Assembler assembler)
    implements CallingConvention<Register> {
  @override
  List<Register> get parameters => const [.rdi, .rsi, .rdx, .rcx, .r8, .r9];

  @override
  List<Register> get callerSaved => const [
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
  void returnValue(Register value) {
    assembler.move(.rax, value);
    assembler.ret();
  }
}
