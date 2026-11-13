import 'package:dartc/assembler/x64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'argument_location.dart';
import 'native_layout.dart';

import 'dart:math' as math;

import 'frame_layout.dart';

/// Classifies System V native calls for macOS and Linux x86-64.
final class X64Abi(@override final Target target)
    implements CallingConvention<CpuRegister> {
  this {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }

  @override
  CallLayout<CpuRegister> classify(NativeSignature signature) {
    signature = signature.resolveAbi(target.abi);
    const general = <Register>[.rdi, .rsi, .rdx, .rcx, .r8, .r9];
    const results = <Register>[.rax, .rdx];
    final storage = NativeLayout(target);
    var integers = 0, floats = 0, stack = 0;
    List<bool>? classes(NativeCompoundType type) {
      final layout = storage.of(type);
      if (layout.size > 16) return null;
      final floating = List<bool>.filled((layout.size + 7) ~/ 8, true);
      for (final member in storage.leaves(type)) {
        final part = storage.of(member.type);
        if (member.offset % part.alignment != 0) return null;
        for (
          var i = member.offset ~/ 8;
          i <= (member.offset + part.size - 1) ~/ 8;
          i++
        ) {
          floating[i] &= member.type.isFloating;
        }
      }
      return floating;
    }

    ArgumentLocation<CpuRegister> assign(
      NativeTypeRef type, {
      bool result = false,
    }) {
      final layout = storage.of(type);
      if (type is NativeCompoundType) {
        final parts = classes(type);
        final floatingCount = parts?.where((floating) => floating).length ?? 0;
        final integerCount = (parts?.length ?? 0) - floatingCount;
        if (parts != null &&
            (result ||
                integers + integerCount <= 6 && floats + floatingCount <= 8)) {
          var resultIntegers = 0, resultFloats = 0;
          return RegisterAggregate([
            for (final (i, floating) in parts.indexed)
              RegisterPart<CpuRegister>(
                floating
                    ? FloatRegister.values[result ? resultFloats++ : floats++]
                    : result
                    ? results[resultIntegers++]
                    : general[integers++],
                i * 8,
                math.min(8, layout.size - i * 8),
              ),
          ]);
        }
        if (result) {
          integers = 1;
          return IndirectArgument<CpuRegister>(
            RegisterArgument(Register.rdi),
            returnedAddress: Register.rax,
          );
        }
      } else if (type.isFloating) {
        if (result || floats < 8) {
          return RegisterArgument(FloatRegister.values[result ? 0 : floats++]);
        }
      } else {
        if (result || integers < 6) {
          return RegisterArgument(result ? Register.rax : general[integers++]);
        }
      }
      final alignment = math.max(8, layout.alignment);
      stack = (stack + alignment - 1) & -alignment;
      final size = (layout.size + 7) & ~7;
      final location = StackArgument<CpuRegister>(
        stack,
        size: size,
        alignment: alignment,
      );
      stack += size;
      return location;
    }

    final result = signature.result.isVoid
        ? null
        : assign(signature.result, result: true);
    final parameters = signature.parameters.map(assign).toList();
    return CallLayout(
      parameters,
      result,
      [
        ...const <Register>[.rax, .rcx, .rdx, .rsi, .rdi, .r8, .r9, .r10, .r11],
        ...FloatRegister.values,
      ],
      registerInputs: {
        if (signature.variadicStart != null) Register.rax: floats,
      },
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
