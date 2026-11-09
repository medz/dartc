import 'package:dartc/assembler/x64.dart';

import 'calling_convention.dart';

/// Emits System V integer calls used by macOS and Linux x86-64.
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
  Register get result => .rax;

  @override
  void enterFrame(int localBytes) {
    _checkFrame(localBytes);
    assembler
      ..push(.rbp)
      ..move(.rbp, .rsp);
    if (localBytes != 0) assembler.addImmediate(.rsp, -localBytes);
  }

  @override
  void leaveFrame(int localBytes) {
    _checkFrame(localBytes);
    if (localBytes != 0) assembler.addImmediate(.rsp, localBytes);
    assembler.pop(.rbp);
  }

  void _checkFrame(int bytes) {
    if (bytes < 0 || bytes > 0x7ffffff0 || bytes % 16 != 0) {
      throw ArgumentError(
        'Expected an aligned frame fitting a signed displacement.',
      );
    }
  }

  @override
  void returnValue(Register value) {
    assembler.move(.rax, value);
    assembler.ret();
  }
}
