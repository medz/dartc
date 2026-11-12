import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

ObjectModule nativeFinalizerCallback(Target target) {
  final List<int> code;
  if (target.architecture == .arm64) {
    final a = arm.Assembler();
    a
      ..load(.x9, .x0, 0)
      ..addImmediate(.x9, .x9, 1)
      ..store(.x9, .x0, 0)
      ..ret();
    code = a.finish();
  } else {
    final a = x64.Assembler();
    a
      ..load(.rax, .rdi, 0)
      ..addImmediate(.rax, 1)
      ..store(.rax, .rdi, 0)
      ..ret();
    code = a.finish();
  }
  return ObjectModule(
    target,
    [Section.code(code), Section.zeroFill(64, alignment: 8)],
    [
      Symbol(
        target.nativeSymbol('resource_released'),
        0,
        0,
        code.length,
        exported: true,
      ),
      Symbol(
        target.nativeSymbol('resource_state'),
        1,
        0,
        64,
        kind: .data,
        exported: true,
      ),
    ],
  );
}

ObjectModule nativeFinalizerExit(Target target) {
  final mac = target.operatingSystem == .macos;
  final code = target.architecture == .arm64
      ? (arm.Assembler()
              ..loadImmediate(.x0, 42)
              ..loadImmediate(mac ? .x16 : .x8, mac ? 1 : 94)
              ..supervisorCall(mac ? 0x80 : 0))
            .finish()
      : (x64.Assembler()
              ..loadImmediate(.rdi, 42)
              ..loadImmediate(.rax, mac ? 0x2000001 : 231)
              ..syscall())
            .finish();
  return ObjectModule(
    target,
    [Section.code(code)],
    [Symbol(target.nativeSymbol('finalizer_exit'), 0, 0, code.length)],
  );
}
