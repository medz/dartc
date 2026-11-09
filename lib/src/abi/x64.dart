import 'package:dartc/assembler/x64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'frame_layout.dart';

/// Classifies System V scalar calls for macOS and Linux x86-64.
final class X64Abi(@override final Target target)
    implements CallingConvention<CpuRegister> {
  this {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }

  @override
  CallLayout<CpuRegister> classify(NativeSignature signature) {
    return .scalars(
      signature,
      general: const <Register>[.rdi, .rsi, .rdx, .rcx, .r8, .r9],
      floating: FloatRegister.values.take(8).toList(),
      generalResult: Register.rax,
      floatingResult: FloatRegister.xmm0,
      clobberedRegisters: [
        ...const <Register>[.rax, .rcx, .rdx, .rsi, .rdi, .r8, .r9, .r10, .r11],
        ...FloatRegister.values,
      ],
    );
  }

  @override
  FrameLayout<CpuRegister> frameLayout({
    required int localBytes,
    required int localAlignment,
    required Iterable<CpuRegister> savedRegisters,
    required int outgoingStackBytes,
  }) => scalarFrame(
    target,
    localBytes: localBytes,
    localAlignment: localAlignment,
    savedRegisters: savedRegisters,
    outgoingStackBytes: outgoingStackBytes,
    frameRegisters: const <Register>[.rbp],
    calleeSaved: const <Register>{.rbx, .r12, .r13, .r14, .r15},
  );

  /// Establishes [frame], preserving parameters and saving the frame pointer.
  void emitPrologue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    assembler
      ..push(.rbp)
      ..move(.rbp, .rsp);
    final bytes = frame.stackBytes - 8;
    if (bytes != 0) assembler.addImmediate(.rsp, -bytes);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      if (key != Register.rbp) assembler.store(key as Register, .rsp, value);
    }
  }

  /// Restores [frame] and returns with the result already in its assigned register.
  void emitEpilogue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      if (key != Register.rbp) assembler.load(key as Register, .rsp, value);
    }
    final bytes = frame.stackBytes - 8;
    if (bytes != 0) assembler.addImmediate(.rsp, bytes);
    assembler
      ..pop(.rbp)
      ..ret();
  }

  void _checkFrame(FrameLayout<CpuRegister> frame) {
    if (frame.target != target) {
      throw ArgumentError('Expected a frame produced for $target.');
    }
  }
}
