import 'package:dartc/assembler/x64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'frame_layout.dart';

/// Classifies System V integer calls for macOS and Linux x86-64.
final class X64Abi(@override final Target target)
    implements CallingConvention<Register> {
  this {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }

  @override
  CallLayout<Register> classify(NativeSignature signature) {
    const parameters = <Register>[.rdi, .rsi, .rdx, .rcx, .r8, .r9];
    return .int64(signature, parameters, .rax, const [
      .rax,
      .rcx,
      .rdx,
      .rsi,
      .rdi,
      .r8,
      .r9,
      .r10,
      .r11,
    ]);
  }

  @override
  FrameLayout<Register> frameLayout({
    required int localBytes,
    required int localAlignment,
    required Iterable<Register> savedRegisters,
    required int outgoingStackBytes,
  }) => integerFrame(
    target,
    localBytes: localBytes,
    localAlignment: localAlignment,
    savedRegisters: savedRegisters,
    outgoingStackBytes: outgoingStackBytes,
    frameRegisters: const [.rbp],
    calleeSaved: const {.rbx, .r12, .r13, .r14, .r15},
  );

  /// Establishes [frame], preserving parameters and saving the frame pointer.
  void emitPrologue(Assembler assembler, FrameLayout<Register> frame) {
    _checkFrame(frame);
    assembler
      ..push(.rbp)
      ..move(.rbp, .rsp);
    final bytes = frame.stackBytes - 8;
    if (bytes != 0) assembler.addImmediate(.rsp, -bytes);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      if (key != .rbp) assembler.storeStack(key, value);
    }
  }

  /// Restores [frame] and returns with the result already in RAX.
  void emitEpilogue(Assembler assembler, FrameLayout<Register> frame) {
    _checkFrame(frame);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      if (key != .rbp) assembler.loadStack(key, value);
    }
    final bytes = frame.stackBytes - 8;
    if (bytes != 0) assembler.addImmediate(.rsp, bytes);
    assembler
      ..pop(.rbp)
      ..ret();
  }

  void _checkFrame(FrameLayout<Register> frame) {
    if (frame.target != target) {
      throw ArgumentError('Expected a frame produced for $target.');
    }
  }
}
