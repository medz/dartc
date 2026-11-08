import 'package:dartc/arm64.dart';

import 'calling_convention.dart';

/// Emits integer calls shared by macOS and Linux AArch64.
final class Arm64Abi(final Assembler assembler)
    implements CallingConvention<Register> {
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
  List<Register> get callerSaved => const [
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
  Register get result => .x0;

  @override
  void enterFrame(int localBytes) {
    _checkFrame(localBytes);
    assembler
      ..addImmediate(.sp, .sp, -localBytes - 16)
      ..store(.x29, .sp, localBytes)
      ..store(.x30, .sp, localBytes + 8)
      ..addImmediate(.x29, .sp, localBytes);
  }

  @override
  void leaveFrame(int localBytes) {
    _checkFrame(localBytes);
    assembler
      ..load(.x29, .sp, localBytes)
      ..load(.x30, .sp, localBytes + 8)
      ..addImmediate(.sp, .sp, localBytes + 16);
  }

  void _checkFrame(int bytes) {
    if (bytes < 0 || bytes > 32752 || bytes % 16 != 0) {
      throw ArgumentError('Expected an aligned frame of at most 32752 bytes.');
    }
  }

  @override
  void returnValue(Register value) {
    assembler.move(.x0, value);
    assembler.ret();
  }
}
