import 'dart:ffi';

import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'calling_convention.dart';
import 'call_layout.dart';
import 'argument_location.dart';
import 'native_layout.dart';

import 'dart:math' as math;

import 'frame_layout.dart';

/// Classifies native calls for macOS and Linux AArch64.
final class Arm64Abi(@override final Target target)
    implements CallingConvention<CpuRegister> {
  this {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }

  @override
  CallLayout<CpuRegister> classify(NativeSignature signature) {
    signature = signature.resolveAbi(target.abi);
    final storage = NativeLayout(target);
    final apple = target.operatingSystem == .macos;
    var integers = 0, floats = 0, stack = 0;
    ArgumentLocation<CpuRegister> stacked(
      NativeTypeRef type, {
      bool variadic = false,
    }) {
      final layout = storage.of(type);
      final alignment = apple && !variadic
          ? layout.alignment
          : math.max(8, layout.alignment);
      stack = (stack + alignment - 1) & -alignment;
      final size = apple && !variadic ? layout.size : (layout.size + 7) & ~7;
      final location = StackArgument<CpuRegister>(
        stack,
        size: size,
        alignment: alignment,
      );
      stack += size;
      return location;
    }

    ArgumentLocation<CpuRegister> assign(
      NativeTypeRef type, {
      bool result = false,
      bool variadic = false,
    }) {
      if (apple && variadic) {
        if (type is NativeCompoundType &&
            storage.of(type).size > 16 &&
            storage.homogeneous(type) == null) {
          return IndirectArgument(
            stacked(NativeTypeRef.of(Pointer<Void>), variadic: true),
          );
        }
        return stacked(type, variadic: true);
      }
      if (type is NativeCompoundType) {
        final layout = storage.of(type);
        final hfa = storage.homogeneous(type);
        if (hfa != null) {
          if (result || floats + hfa.length <= 8) {
            final first = result ? 0 : floats;
            if (!result) floats += hfa.length;
            return RegisterAggregate([
              for (final (i, member) in hfa.indexed)
                RegisterPart<CpuRegister>(
                  FloatRegister.values[first + i],
                  member.offset,
                  member.type.nativeSize,
                ),
            ]);
          }
          floats = 8;
          return stacked(type);
        }
        if (layout.size > 16) {
          return IndirectArgument(
            result
                ? const RegisterArgument(Register.x8)
                : assign(NativeTypeRef.of(Pointer<Void>)),
          );
        }
        final words = (layout.size + 7) ~/ 8;
        if (!result && !apple && layout.alignment == 16) {
          integers = (integers + 1) & ~1;
        }
        if (result || integers + words <= 8) {
          final first = result ? 0 : integers;
          if (!result) integers += words;
          return RegisterAggregate([
            for (var i = 0; i < words; i++)
              RegisterPart<CpuRegister>(
                Register.values[first + i],
                i * 8,
                math.min(8, layout.size - i * 8),
              ),
          ]);
        }
        integers = 8;
        return stacked(type);
      }
      if (type.isFloating) {
        if (result || floats < 8) {
          return RegisterArgument(FloatRegister.values[result ? 0 : floats++]);
        }
      } else {
        if (result || integers < 8) {
          return RegisterArgument(Register.values[result ? 0 : integers++]);
        }
      }
      return stacked(type);
    }

    final result = signature.result.isVoid
        ? null
        : assign(signature.result, result: true);
    return CallLayout(
      [
        for (final (i, type) in signature.parameters.indexed)
          assign(
            type,
            variadic:
                signature.variadicStart != null &&
                i >= signature.variadicStart!,
          ),
      ],
      result,
      [
        for (var i = 0; i <= 17; i++) Register.values[i],
        if (!apple) Register.x18,
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

  /// Establishes [frame], using IP0 for large offsets and preserving arguments.
  void emitPrologue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    assembler.addImmediate(.sp, .sp, -frame.stackBytes);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      final large = value > 32760;
      if (large) assembler.addImmediate(.x16, .sp, value);
      switch (key) {
        case Register():
          assembler.store(key, large ? .x16 : .sp, large ? 0 : value);
        case FloatRegister():
          assembler.storeDouble(key, large ? .x16 : .sp, large ? 0 : value);
      }
    }
    assembler.addImmediate(.x29, .sp, frame.savedRegisters[Register.x29]!);
  }

  /// Restores [frame] and returns with the result already in its assigned register.
  void emitEpilogue(Assembler assembler, FrameLayout<CpuRegister> frame) {
    _checkFrame(frame);
    for (final MapEntry(:key, :value) in frame.savedRegisters.entries) {
      final large = value > 32760;
      if (large) assembler.addImmediate(.x16, .sp, value);
      switch (key) {
        case Register():
          assembler.load(key, large ? .x16 : .sp, large ? 0 : value);
        case FloatRegister():
          assembler.loadDouble(key, large ? .x16 : .sp, large ? 0 : value);
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
