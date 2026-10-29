import 'arm64.dart';
import 'code.dart';
import 'frame.dart';
import 'library_abi.dart';
import 'target.dart';
import 'types.dart';

void _memory(int opcode, int register, int base, int offset, int width) {
  if (offset ~/ width < 4096) {
    codeWord(opcode | ((offset ~/ width) << 10) | (base << 5) | register);
  } else {
    if (base == 31) {
      codeWord(0x910003eb); // mov x11, sp
      base = 11;
    }
    armConstant(10, offset);
    codeWord(0x8b0a000a | (base << 5));
    codeWord(opcode | (10 << 5) | register);
  }
}

void _extend(int kind, int target, int source) {
  var width = 0;
  if (kind == ffiInt8 || kind == ffiUint8) width = 8;
  if (kind == ffiInt16 || kind == ffiUint16) width = 16;
  if (kind == ffiInt32 || kind == ffiUint32) width = 32;
  if (kind == ffiBool) width = 1;
  final signed = kind == ffiInt8 || kind == ffiInt16 || kind == ffiInt32;
  if (width == 0) {
    armMove(target, source);
  } else {
    codeWord(
      (signed ? 0x93400000 : 0xd3400000) |
          ((width - 1) << 10) |
          (source << 5) |
          target,
    );
  }
}

// C uses separate integer/FP argument banks and packed Darwin stack arguments.
// Internal Dart calls pass every scalar as a 64-bit word, including doubles.
int emitArm64Export(int function, int type) {
  if (libraryDirectCall(type)) return functionOffsets[function];
  final entry = codeSize;
  final signature = functionSignature(type);
  final parameters = signature.parameters;
  final stackWords = parameters.length > 8 ? parameters.length - 8 : 0;
  codeWord(0xa9bf7bfd); // stp x29, x30, [sp, #-16]!
  codeWord(0x910003fd); // mov x29, sp
  var frame = alignFrame(parameters.length * 8);
  while (frame >= 4096) {
    codeWord(0xd14007ff);
    frame -= 4096;
  }
  if (frame != 0) codeWord(0xd10003ff | (frame << 10));
  var integer = 0;
  var floating = 0;
  var stack = 16;
  for (var i = 0; i < parameters.length; i++) {
    final kind = ffiKind(parameters[i]);
    final width = libraryTypeSize(parameters[i]);
    final fp = kind == ffiFloat || kind == ffiDouble;
    final register = fp ? floating++ : integer++;
    if (register < 8) {
      if (fp) {
        if (kind == ffiFloat) {
          codeWord(0x1e22c010 | (register << 5)); // fcvt d16, sN
          armMove(9, floatRegisterBase + 16);
        } else {
          armMove(9, floatRegisterBase + register);
        }
      } else {
        _extend(kind, 9, register);
      }
    } else {
      stack = (stack + width - 1) & -width;
      final opcode = switch (width) {
        1 => 0x39400000,
        2 => 0x79400000,
        4 => 0xb9400000,
        _ => 0xf9400000,
      };
      _memory(opcode, 9, 29, stack, width);
      if (kind == ffiFloat) {
        codeWord(0x1e270130); // fmov s16, w9
        codeWord(0x1e22c210); // fcvt d16, s16
        armMove(9, floatRegisterBase + 16);
      } else if (!fp) {
        _extend(kind, 9, 9);
      }
      stack += width;
    }
    // Spill all incoming values before overwriting any C argument register.
    final slot = i < 8 ? stackWords + i : i - 8;
    _memory(0xf9000000, 9, 31, slot * 8, 8);
  }
  for (var i = 0; i < parameters.length && i < 8; i++)
    _memory(0xf9400000, i, 31, (stackWords + i) * 8, 8);
  armCall(function);
  final result = ffiKind(signature.result);
  if (result == ffiDouble || result == ffiFloat) {
    armMove(floatRegisterBase, 0);
    if (result == ffiFloat) codeWord(0x1e624000); // fcvt s0, d0
  } else if (result != ffiVoid) {
    _extend(result, 0, 0);
  }
  codeWord(0x910003bf); // mov sp, x29
  codeWord(0xa8c17bfd); // ldp x29, x30, [sp], #16
  codeWord(0xd65f03c0);
  return entry;
}
