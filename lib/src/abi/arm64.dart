import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'frame_layout.dart';

/// Classifies scalar calls for macOS and Linux AArch64.
final class Arm64Abi(@override final Target target)
    implements CallingConvention<CpuRegister> {
  this {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }

  @override
  CallLayout<CpuRegister> classify(NativeSignature signature) {
    return .scalars(
      signature,
      general: const <Register>[.x0, .x1, .x2, .x3, .x4, .x5, .x6, .x7],
      floating: FloatRegister.values.take(8).toList(),
      generalResult: Register.x0,
      floatingResult: FloatRegister.d0,
      packedStack: target.operatingSystem == .macos,
      clobberedRegisters: [
        for (var i = 0; i <= 17; i++) Register.values[i],
        if (target.operatingSystem == .linux) Register.x18,
        Register.x30,
        ...FloatRegister.values.take(8),
        ...FloatRegister.values.skip(16),
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
    frameRegisters: const <Register>[.x29, .x30],
    calleeSaved: {
      ...const <Register>[
        .x19,
        .x20,
        .x21,
        .x22,
        .x23,
        .x24,
        .x25,
        .x26,
        .x27,
        .x28,
      ],
      ...FloatRegister.values.skip(8).take(8),
    },
  );

  /// Establishes [frame] without changing parameter registers or flags.
  void emitPrologue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    assembler.addImmediate(.sp, .sp, -frame.stackBytes);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      switch (key) {
        case Register():
          assembler.store(key, .sp, value);
        case FloatRegister():
          assembler.storeDouble(key, .sp, value);
      }
    }
    assembler.addImmediate(.x29, .sp, frame.savedRegisters[Register.x29]!);
  }

  /// Restores [frame] and returns with the result already in its assigned register.
  void emitEpilogue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      switch (key) {
        case Register():
          assembler.load(key, .sp, value);
        case FloatRegister():
          assembler.loadDouble(key, .sp, value);
      }
    }
    assembler
      ..addImmediate(.sp, .sp, frame.stackBytes)
      ..ret();
  }

  void _checkFrame(FrameLayout<CpuRegister> frame) {
    if (frame.target != target) {
      throw ArgumentError('Expected a frame produced for $target.');
    }
  }
}
