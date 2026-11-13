import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Installs a process-local filter denying getrandom on Linux ARM64.
ObjectModule denyEntropy() {
  final a = Assembler(), done = a.label();
  a.addImmediate(.sp, .sp, -48);
  // BPF: load syscall number, deny getrandom with EACCES, allow all others.
  for (final (i, word) in [
    0x20,
    (278 << 32) | 0x01000015,
    (0x5000d << 32) | 6,
    (0x7fff0000 << 32) | 6,
    4,
  ].indexed) {
    a
      ..loadImmediate(.x9, word)
      ..store(.x9, .sp, i * 8);
  }
  a
    ..addImmediate(.x9, .sp, 0)
    ..store(.x9, .sp, 40)
    ..loadImmediate(.x0, 38) // PR_SET_NO_NEW_PRIVS.
    ..loadImmediate(.x1, 1)
    ..loadImmediate(.x2, 0)
    ..loadImmediate(.x3, 0)
    ..loadImmediate(.x4, 0)
    ..loadImmediate(.x8, 167)
    ..supervisorCall(0)
    ..compare(.x0, .x2)
    ..setCondition(.x9, .equal)
    ..branchZero(.x9, done)
    ..loadImmediate(.x0, 22) // PR_SET_SECCOMP, SECCOMP_MODE_FILTER.
    ..loadImmediate(.x1, 2)
    ..addImmediate(.x2, .sp, 32)
    ..loadImmediate(.x8, 167)
    ..supervisorCall(0)
    ..bind(done)
    ..addImmediate(.sp, .sp, 48)
    ..ret();
  final code = a.finish();
  return ObjectModule(
    const Target(.linux, .arm64),
    [Section.code(code)],
    [Symbol('deny_entropy', 0, 0, code.length)],
  );
}
