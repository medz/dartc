import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test('ARM64 frames address saved registers beyond the scaled-load range', () {
    final abi = Arm64Abi(const Target(.macos, .arm64));
    final frame = abi.frameLayout(
      localBytes: 128 * 1024,
      localAlignment: 16,
      savedRegisters: [arm.Register.x19, arm.FloatRegister.d8],
      outgoingStackBytes: 32,
    );
    final code = arm.Assembler();
    abi.emitPrologue(code, frame);
    abi.emitEpilogue(code, frame);
    expect(frame.savedRegisters[arm.Register.x19], 128 * 1024 + 32);
    expect(code.finish(), isNotEmpty);
  });
  test('float and double share FP banks but retain distinct stack widths', () {
    for (final os in OperatingSystem.values) {
      for (final abi in <CallingConvention<Object>>[
        Arm64Abi(Target(os, .arm64)),
        X64Abi(Target(os, .x64)),
      ]) {
        final packed = abi.target == const Target(.macos, .arm64);
        final layout = abi.classify(
          NativeSignature(Float, [
            for (var i = 0; i < 4; i++) ...[Float, Double],
            Float,
            Float,
            Double,
          ]),
        );
        expect(
          layout.parameters.take(8),
          everyElement(isA<RegisterArgument>()),
        );
        final slots = layout.parameters.skip(8).cast<StackArgument>();
        expect(slots.map((s) => s.offset), packed ? [0, 4, 8] : [0, 8, 16]);
        expect(slots.map((s) => s.size), packed ? [4, 4, 8] : [8, 8, 8]);
        expect(layout.stackBytes, packed ? 16 : 32);
        expect(
          layout.resultRegister,
          abi.target.architecture == .arm64
              ? arm.FloatRegister.d0
              : x64.FloatRegister.xmm0,
        );
      }
    }
  });

  test('narrow stack slots follow the selected platform ABI', () {
    for (final os in OperatingSystem.values) {
      final cases = <(CallingConvention<Object>, int, bool)>[
        (Arm64Abi(Target(os, .arm64)), 8, os == .macos),
        (X64Abi(Target(os, .x64)), 6, false),
      ];
      for (final (abi, registers, packed) in cases) {
        final layout = abi.classify(
          NativeSignature(Int8, [
            ...List.filled(registers, Int64),
            Int8,
            Uint8,
            Int16,
            Uint16,
            Int32,
            Uint32,
            Int64,
          ]),
        );
        final slots = layout.parameters.whereType<StackArgument>();
        expect(
          slots.map((s) => s.offset),
          packed ? [0, 1, 2, 4, 8, 12, 16] : [0, 8, 16, 24, 32, 40, 48],
        );
        expect(
          slots.map((s) => s.size),
          packed ? [1, 1, 2, 2, 4, 4, 8] : List.filled(7, 8),
        );
        expect(layout.stackBytes, packed ? 32 : 64);
      }
    }
    for (final (offset, size) in [(0, 0), (0, 3), (-1, 1), (1, 2)]) {
      expect(() => StackArgument<int>(offset, size: size), throwsArgumentError);
    }
  });

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
        expect(frame.returnAddressOffset, 72);
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
    test('$os exhausts integer and double argument banks independently', () {
      final signature = NativeSignature(Double, [
        Pointer<Int64>,
        for (var i = 0; i < 9; i++) ...[Double, Int64],
      ]);
      final armCall = armAbi.classify(signature),
          x64Call = x64Abi.classify(signature);
      expect(armCall.resultRegister, arm.FloatRegister.d0);
      expect(x64Call.resultRegister, x64.FloatRegister.xmm0);
      expect(
        armCall.parameters.whereType<RegisterArgument<arm.CpuRegister>>().map(
          (v) => v.register,
        ),
        [
          arm.Register.x0,
          for (var i = 0; i < 8; i++) ...[
            arm.FloatRegister.values[i],
            if (i < 7) arm.Register.values[i + 1],
          ],
        ],
      );
      expect(
        x64Call.parameters.whereType<RegisterArgument<x64.CpuRegister>>().map(
          (v) => v.register,
        ),
        [
          x64.Register.rdi,
          for (var i = 0; i < 8; i++) ...[
            x64.FloatRegister.values[i],
            if (i < 5) <x64.Register>[.rsi, .rdx, .rcx, .r8, .r9][i],
          ],
        ],
      );
      expect(
        armCall.parameters.whereType<StackArgument>().map((v) => v.offset),
        [0, 8, 16],
      );
      expect(
        x64Call.parameters.whereType<StackArgument>().map((v) => v.offset),
        [0, 8, 16, 24, 32],
      );
      expect(armCall.stackBytes, 32);
      expect(x64Call.stackBytes, 48);
      expect(
        armCall.clobberedRegisters,
        containsAll([arm.FloatRegister.d0, arm.FloatRegister.d31]),
      );
      expect(armCall.clobberedRegisters, isNot(contains(arm.FloatRegister.d8)));
      expect(x64Call.clobberedRegisters, containsAll(x64.FloatRegister.values));
      final frame = armAbi.frameLayout(
        localBytes: 0,
        localAlignment: 8,
        savedRegisters: <arm.FloatRegister>[.d8, .d15],
        outgoingStackBytes: 0,
      );
      expect(frame.savedRegisters[arm.FloatRegister.d8], 0);
      expect(frame.savedRegisters[arm.FloatRegister.d15], 8);
      expect(
        () => x64Abi.frameLayout(
          localBytes: 0,
          localAlignment: 8,
          savedRegisters: <x64.FloatRegister>[.xmm8],
          outgoingStackBytes: 0,
        ),
        throwsArgumentError,
      );
    });
    layouts<arm.CpuRegister>(armAbi, <arm.Register>[
      .x19,
      .x20,
    ], arm.Register.x0);
    layouts<x64.CpuRegister>(x64Abi, <x64.Register>[
      .rbx,
      .r12,
    ], x64.Register.rax);
    test(
      '$os shares word locations for pointers and integers with void results',
      () {
        final signature = NativeSignature(Void, [
          for (var i = 0; i < 5; i++) ...[Pointer<Int64>, Int64],
        ]);
        for (final (call, registers) in [
          (armAbi.classify(signature), 8),
          (x64Abi.classify(signature), 6),
        ]) {
          expect(call.resultRegister, isNull);
          expect(
            call.parameters.take(registers).every((p) => p is RegisterArgument),
            isTrue,
          );
          expect(
            call.parameters
                .skip(registers)
                .cast<StackArgument>()
                .map((p) => p.offset),
            [for (var i = 0; i < 10 - registers; i++) i * 8],
          );
          expect(call.stackBytes, (10 - registers) * 8);
        }
        expect(
          armAbi.classify(NativeSignature(Pointer<Int64>, [])).resultRegister,
          arm.Register.x0,
        );
        expect(
          x64Abi.classify(NativeSignature(Pointer<Int64>, [])).resultRegister,
          x64.Register.rax,
        );
      },
    );
    test('$os classifies Int64 locations and actual call clobbers', () {
      final armCall = armAbi.classify(
        NativeSignature(Int64, List.filled(8, Int64)),
      );
      final x64Call = x64Abi.classify(
        NativeSignature(Int64, List.filled(6, Int64)),
      );
      expect(
        armCall.parameters.whereType<RegisterArgument<arm.CpuRegister>>().map(
          (location) => location.register,
        ),
        <arm.Register>[.x0, .x1, .x2, .x3, .x4, .x5, .x6, .x7],
      );
      expect(
        x64Call.parameters.whereType<RegisterArgument<x64.CpuRegister>>().map(
          (location) => location.register,
        ),
        <x64.Register>[.rdi, .rsi, .rdx, .rcx, .r8, .r9],
      );
      expect(armCall.resultRegister, arm.Register.x0);
      expect(x64Call.resultRegister, x64.Register.rax);
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
      expect(
        armAbi
            .classify(NativeSignature(Int64, List.filled(0, Int64)))
            .parameters,
        isEmpty,
      );
      expect(
        x64Abi
            .classify(NativeSignature(Int64, List.filled(0, Int64)))
            .parameters,
        isEmpty,
      );
      for (final call in [
        armAbi.classify(NativeSignature(Int64, List.filled(9, Int64))),
        x64Abi.classify(NativeSignature(Int64, List.filled(7, Int64))),
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
        (armAbi.classify(NativeSignature(Int64, List.filled(11, Int64))), 8),
        (x64Abi.classify(NativeSignature(Int64, List.filled(9, Int64))), 6),
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
      () => CallLayout(
        [RegisterArgument(1), RegisterArgument(1)],
        RegisterArgument(0),
        {0, 1},
      ),
      throwsArgumentError,
    );
    expect(
      () => CallLayout([RegisterArgument(1)], RegisterArgument(0), {1}),
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
        () => CallLayout(
          offsets.map(StackArgument<int>.new),
          RegisterArgument(0),
          {0},
        ),
        throwsArgumentError,
      );
    }
    expect(() => NativeSignature(Int64, [Void]), throwsUnsupportedError);
  });
}
