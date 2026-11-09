import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'frame_layout.dart';

/// Classifies integer calls and emits frames for macOS and Linux AArch64.
final class Arm64Abi(@override final Target target)
    implements CallingConvention<Register> {
  this {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }

  @override
  CallLayout<Register> classify(NativeSignature signature) {
    const parameters = <Register>[.x0, .x1, .x2, .x3, .x4, .x5, .x6, .x7];
    return .int64(signature, parameters, .x0, [
      for (var i = 0; i <= 17; i++) Register.values[i],
      if (target.operatingSystem == .linux) .x18,
      .x30,
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
    frameRegisters: const [.x29, .x30],
    calleeSaved: const {
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
    },
  );

  /// Establishes [frame] without changing parameter registers or flags.
  void emitPrologue(Assembler assembler, FrameLayout<Register> frame) {
    _checkFrame(frame);
    assembler.addImmediate(.sp, .sp, -frame.stackBytes);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      assembler.store(key, .sp, value);
    }
    assembler.addImmediate(.x29, .sp, frame.savedRegisters[Register.x29]!);
  }

  /// Restores [frame] and returns with the result already in X0.
  void emitEpilogue(Assembler assembler, FrameLayout<Register> frame) {
    _checkFrame(frame);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      assembler.load(key, .sp, value);
    }
    assembler
      ..addImmediate(.sp, .sp, frame.stackBytes)
      ..ret();
  }

  void _checkFrame(FrameLayout<Register> frame) {
    if (frame.target != target) {
      throw ArgumentError('Expected a frame produced for $target.');
    }
  }
}
