import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

ObjectModule restrictAddressSpace(Target target) {
  if (target.operatingSystem != .linux) {
    throw ArgumentError('RLIMIT_AS failure fixture requires Linux.');
  }
  final Uint8List code;
  if (target.architecture == .arm64) {
    final a = arm.Assembler(), done = a.label();
    a
      ..addImmediate(.sp, .sp, -16)
      ..loadImmediate(.x9, 0)
      ..store(.x9, .sp, 0)
      ..store(.x9, .sp, 8)
      ..loadImmediate(.x0, 9)
      ..addImmediate(.x1, .sp, 0)
      ..loadImmediate(.x8, 164)
      ..supervisorCall(0)
      ..branchZero(.x0, done)
      ..loadImmediate(.x0, 72)
      ..loadImmediate(.x8, 94)
      ..supervisorCall(0)
      ..bind(done)
      ..addImmediate(.sp, .sp, 16)
      ..ret();
    code = a.finish();
  } else {
    final a = x64.Assembler(), done = a.label();
    a
      ..addImmediate(.rsp, -16)
      ..loadImmediate(.r10, 0)
      ..store(.r10, .rsp, 0)
      ..store(.r10, .rsp, 8)
      ..loadImmediate(.rdi, 9)
      ..move(.rsi, .rsp)
      ..loadImmediate(.rax, 160)
      ..syscall()
      ..test(.rax)
      ..jumpCondition(.equal, done)
      ..loadImmediate(.rdi, 72)
      ..loadImmediate(.rax, 231)
      ..syscall()
      ..bind(done)
      ..addImmediate(.rsp, 16)
      ..ret();
    code = a.finish();
  }
  return ObjectModule(
    target,
    [Section.code(code)],
    [Symbol('heap_limit', 0, 0, code.length)],
  );
}
