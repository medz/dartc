import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

ObjectModule floatingFrames(Target target) {
  final List<int> outer, inner;
  final Fixup call;
  if (target.architecture == .arm64) {
    final abi = Arm64Abi(target), code = arm.Assembler();
    final frame = abi.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: <arm.FloatRegister>[.d8, .d15],
      outgoingStackBytes: 0,
    );
    abi.emitPrologue(code, frame);
    code
      ..moveDouble(.d8, .d0)
      ..loadImmediate(.x9, 0x400c000000000000)
      ..moveBitsToDouble(.d15, .x9);
    call = code.call();
    code.addDouble(.d0, .d8, .d15);
    abi.emitEpilogue(code, frame);
    outer = code.finish();
    final callee = arm.Assembler();
    abi.emitPrologue(callee, frame);
    callee
      ..loadImmediate(.x9, 0x408f400000000000)
      ..moveBitsToDouble(.d8, .x9)
      ..moveDouble(.d15, .d8);
    abi.emitEpilogue(callee, frame);
    inner = callee.finish();
  } else {
    final abi = X64Abi(target), code = x64.Assembler();
    final frame = abi.frameLayout(
      localBytes: 8,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: 0,
    );
    abi.emitPrologue(code, frame);
    code.storeDouble(.xmm0, .rsp, frame.localOffset);
    call = code.call();
    code
      ..loadDouble(.xmm1, .rsp, frame.localOffset)
      ..addDouble(.xmm0, .xmm1);
    abi.emitEpilogue(code, frame);
    outer = code.finish();
    final callee = x64.Assembler()
      ..loadImmediate(.rax, 0x400c000000000000)
      ..moveBitsToDouble(.xmm0, .rax)
      ..moveDouble(.xmm1, .xmm0)
      ..ret();
    inner = callee.finish();
  }
  return .new(
    target,
    [
      Section.code([...outer, ...inner]),
    ],
    [
      Symbol(
        target.nativeSymbol('floating_frame'),
        0,
        0,
        outer.length,
        exported: true,
      ),
      Symbol('callee', 0, outer.length, inner.length, binding: .local),
    ],
    relocations: [Relocation(0, call.offset, call.encoding, 1)],
  );
}
