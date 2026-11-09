import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  void layouts<R>(CallingConvention<R> abi, List<R> saved, R volatile) {
    test(
      '${abi.target} separates stack regions and rejects invalid demands',
      () {
        final frame = abi.frameLayout(
          localBytes: 9,
          localAlignment: 16,
          savedRegisters: saved,
          outgoingStackBytes: 24,
        );
        expect(frame.localOffset, 32);
        expect(frame.localBytes, 9);
        expect(frame.outgoingStackBytes, 24);
        expect(frame.savedRegisters[saved[0]], 48);
        expect(frame.savedRegisters[saved[1]], 56);
        expect(frame.stackBytes, abi.target.architecture == .arm64 ? 80 : 72);
        expect(frame.incomingStackOffset, 80);
        expect(() => frame.savedRegisters.clear(), throwsUnsupportedError);
        for (final (bytes, alignment, registers, outgoing) in [
          (-1, 8, saved, 0),
          (8, 0, saved, 0),
          (8, 3, saved, 0),
          (8, 32, saved, 0),
          (8, 8, saved, -1),
          (0x7fffffff, 8, saved, 0),
          (8, 8, [saved[0], saved[0]], 0),
          (8, 8, [volatile], 0),
        ]) {
          expect(
            () => abi.frameLayout(
              localBytes: bytes,
              localAlignment: alignment,
              savedRegisters: registers,
              outgoingStackBytes: outgoing,
            ),
            throwsArgumentError,
          );
        }
      },
    );
  }

  for (final os in OperatingSystem.values) {
    final armAbi = Arm64Abi(Target(os, .arm64)),
        x64Abi = X64Abi(Target(os, .x64));
    layouts<arm.Register>(armAbi, <arm.Register>[.x19, .x20], .x0);
    layouts<x64.Register>(x64Abi, <x64.Register>[.rbx, .r12], .rax);
    test('$os classifies Int64 locations and actual call clobbers', () {
      final armCall = armAbi.classify(NativeSignature.int64(8));
      final x64Call = x64Abi.classify(NativeSignature.int64(6));
      expect(
        armCall.parameters.whereType<RegisterArgument<arm.Register>>().map(
          (location) => location.register,
        ),
        <arm.Register>[.x0, .x1, .x2, .x3, .x4, .x5, .x6, .x7],
      );
      expect(
        x64Call.parameters.whereType<RegisterArgument<x64.Register>>().map(
          (location) => location.register,
        ),
        <x64.Register>[.rdi, .rsi, .rdx, .rcx, .r8, .r9],
      );
      expect(armCall.result, arm.Register.x0);
      expect(x64Call.result, x64.Register.rax);
      expect(
        armCall.clobberedRegisters,
        containsAll(<arm.Register>[.x8, .x16, .x17, .x30]),
      );
      expect(
        armCall.clobberedRegisters.contains(arm.Register.x18),
        os == .linux,
      );
      expect(armCall.clobberedRegisters, isNot(contains(arm.Register.x19)));
      expect(
        x64Call.clobberedRegisters,
        containsAll(<x64.Register>[.r10, .r11]),
      );
      expect(x64Call.clobberedRegisters, isNot(contains(x64.Register.rbx)));
      expect(armCall.clobbersFlags && x64Call.clobbersFlags, isTrue);
      expect(armCall.stackBytes + x64Call.stackBytes, 0);
      expect(() => armCall.parameters.clear(), throwsUnsupportedError);
      expect(() => x64Call.clobberedRegisters.clear(), throwsUnsupportedError);
      expect(armAbi.classify(NativeSignature.int64(0)).parameters, isEmpty);
      expect(x64Abi.classify(NativeSignature.int64(0)).parameters, isEmpty);
      for (final call in [
        armAbi.classify(NativeSignature.int64(9)),
        x64Abi.classify(NativeSignature.int64(7)),
      ]) {
        expect(
          call.parameters.last,
          isA<StackArgument>().having(
            (location) => location.offset,
            'offset',
            0,
          ),
        );
        expect(call.stackBytes, 16);
      }
      for (final (call, registerCount) in [
        (armAbi.classify(NativeSignature.int64(11)), 8),
        (x64Abi.classify(NativeSignature.int64(9)), 6),
      ]) {
        expect(call.parameters, hasLength(registerCount + 3));
        expect(
          call.parameters
              .skip(registerCount)
              .cast<StackArgument>()
              .map((location) => location.offset),
          [0, 8, 16],
        );
        expect(call.stackBytes, 32);
      }
    });
  }
  test('rejects incompatible targets and frame provenance before emission', () {
    expect(() => Arm64Abi(const Target(.linux, .x64)), throwsArgumentError);
    expect(() => X64Abi(const Target(.linux, .arm64)), throwsArgumentError);
    final armCode = arm.Assembler(), x64Code = x64.Assembler();
    final armFrame = Arm64Abi(const Target(.linux, .arm64)).frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: 0,
    );
    final x64Frame = X64Abi(const Target(.linux, .x64)).frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: 0,
    );
    expect(
      () =>
          Arm64Abi(const Target(.macos, .arm64))
              .emitPrologue(armCode, armFrame),
      throwsArgumentError,
    );
    expect(
      () => X64Abi(const Target(.macos, .x64)).emitEpilogue(x64Code, x64Frame),
      throwsArgumentError,
    );
    expect(armCode.finish(), isEmpty);
    expect(x64Code.finish(), isEmpty);
    expect(
      () => CallLayout([RegisterArgument(1), RegisterArgument(1)], 0, {0, 1}),
      throwsArgumentError,
    );
    expect(
      () => CallLayout([RegisterArgument(1)], 0, {1}),
      throwsArgumentError,
    );
    for (final offset in [-8, -1, 1, 7]) {
      expect(() => StackArgument<int>(offset), throwsArgumentError);
    }
    for (final offsets in [
      [8],
      [0, 0],
      [0, 16],
    ]) {
      expect(
        () => CallLayout(offsets.map(StackArgument<int>.new), 0, {0}),
        throwsArgumentError,
      );
    }
    expect(() => NativeSignature.int64(-1), throwsArgumentError);
  });
}
