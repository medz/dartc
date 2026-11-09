import 'package:dartc/abi.dart';
import 'package:dartc/object.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/target.dart';

ObjectModule frames(Target target) {
  final List<int> outer, inner;
  final Fixup call;
  if (target.architecture == .arm64) {
    final abi = Arm64Abi(target), code = arm.Assembler();
    final frame = abi.frameLayout(
      localBytes: 8,
      localAlignment: 16,
      savedRegisters: <arm.Register>[.x19, .x20],
      outgoingStackBytes: 24,
    );
    abi.emitPrologue(code, frame);
    code
      ..store(.x0, .sp, frame.localOffset)
      ..loadImmediate(.x19, 41)
      ..loadImmediate(.x20, 13);
    call = code.call();
    code
      ..load(.x1, .sp, frame.localOffset)
      ..add(.x0, .x0, .x1)
      ..add(.x0, .x0, .x19)
      ..add(.x0, .x0, .x20);
    abi.emitEpilogue(code, frame);
    outer = code.finish();
    final callee = arm.Assembler();
    abi.emitPrologue(callee, frame);
    callee
      ..loadImmediate(.x19, 99)
      ..loadImmediate(.x20, 77)
      ..loadImmediate(.x0, 7);
    abi.emitEpilogue(callee, frame);
    inner = callee.finish();
  } else {
    final abi = X64Abi(target), code = x64.Assembler();
    final frame = abi.frameLayout(
      localBytes: 8,
      localAlignment: 16,
      savedRegisters: <x64.Register>[.rbx, .r12],
      outgoingStackBytes: 24,
    );
    abi.emitPrologue(code, frame);
    code
      ..store(.rdi, .rsp, frame.localOffset)
      ..loadImmediate(.rbx, 41)
      ..loadImmediate(.r12, 13);
    call = code.call();
    code
      ..load(.rsi, .rsp, frame.localOffset)
      ..add(.rax, .rsi)
      ..add(.rax, .rbx)
      ..add(.rax, .r12);
    abi.emitEpilogue(code, frame);
    outer = code.finish();
    final callee = x64.Assembler();
    abi.emitPrologue(callee, frame);
    callee
      ..loadImmediate(.rbx, 99)
      ..loadImmediate(.r12, 77)
      ..loadImmediate(.rax, 7);
    abi.emitEpilogue(callee, frame);
    inner = callee.finish();
  }
  return .new(
    target,
    [
      Section.code([...outer, ...inner]),
    ],
    [
      Symbol(
        target.nativeSymbol('frame_round_trip'),
        0,
        0,
        outer.length,
        exported: true,
      ),
      Symbol('callee', 0, outer.length, inner.length, binding: .local),
    ],
    relocations: [Relocation.instruction(0, call.offset, call.encoding, 1)],
  );
}
