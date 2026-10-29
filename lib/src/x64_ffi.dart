import 'code.dart';
import 'frame.dart';
import 'library_abi.dart';
import 'types.dart';
import 'x64.dart';

void _extend(int kind, int source) {
  if (kind == ffiInt8 ||
      kind == ffiInt16 ||
      kind == ffiUint8 ||
      kind == ffiUint16) {
    final signed = kind == ffiInt8 || kind == ffiInt16;
    xRex(signed, xRax, source);
    codeByte(0x0f);
    codeByte(switch (kind) {
      ffiInt8 => 0xbe,
      ffiInt16 => 0xbf,
      ffiUint8 => 0xb6,
      _ => 0xb7,
    });
    codeByte(0xc0 | (source & 7));
  } else if (kind == ffiInt32) {
    xRex(true, xRax, source);
    codeByte(0x63); // movsxd rax, source
    codeByte(0xc0 | (source & 7));
  } else if (kind == ffiUint32) {
    xRex(false, source, xRax);
    codeByte(0x89); // mov eax, source32
    codeByte(0xc0 | ((source & 7) << 3));
  } else {
    xMove(xRax, source);
    if (kind == ffiBool) xImmediate(4, xRax, 1);
  }
}

void _convertFloat(int target, int source, bool widen) {
  codeByte(widen ? 0xf3 : 0xf2);
  xRex(false, target, source);
  codeByte(0x0f);
  codeByte(0x5a); // cvtss2sd / cvtsd2ss
  codeByte(0xc0 | ((target & 7) << 3) | (source & 7));
}

// System V C calls use six integer and eight SSE arguments independently.
// Internal Dart calls carry every scalar in a word, including binary64 bits.
int emitX64Export(int function, int type) {
  if (libraryDirectCall(type)) return functionOffsets[function];
  final entry = codeSize;
  final signature = functionSignature(type);
  final parameters = signature.parameters;
  final stackWords = parameters.length > 6 ? parameters.length - 6 : 0;
  xPush(xRbp);
  xMove(xRbp, xRsp);
  final frame = alignFrame(parameters.length * 8);
  if (frame != 0) xImmediate(5, xRsp, frame);
  var integer = 0;
  var floating = 0;
  var stack = 16;
  for (var i = 0; i < parameters.length; i++) {
    final kind = ffiKind(parameters[i]);
    final fp = kind == ffiFloat || kind == ffiDouble;
    final register = fp ? floating++ : integer++;
    if (register < (fp ? 8 : 6)) {
      if (fp) {
        if (kind == ffiFloat) {
          _convertFloat(15, register, true);
          xFloatBits(15, xRax, false);
        } else {
          xFloatBits(register, xRax, false);
        }
      } else {
        _extend(kind, xArguments[register]);
      }
    } else {
      xLoad(xRax, xRbp, stack);
      stack += 8;
      if (kind == ffiFloat) {
        xFloatBits(15, xRax, true);
        _convertFloat(15, 15, true);
        xFloatBits(15, xRax, false);
      } else if (!fp) {
        _extend(kind, xRax);
      }
    }
    // Preserve all incoming registers before arranging the internal call.
    final slot = i < 6 ? stackWords + i : i - 6;
    xStore(xRsp, slot * 8, xRax);
  }
  for (var i = 0; i < parameters.length && i < 6; i++)
    xLoad(xArguments[i], xRsp, (stackWords + i) * 8);
  xCall(function);
  final result = ffiKind(signature.result);
  if (result == ffiFloat || result == ffiDouble) {
    xFloatBits(0, xRax, true);
    if (result == ffiFloat) _convertFloat(0, 0, false);
  } else if (result != ffiVoid) {
    _extend(result, xRax);
  }
  xMove(xRsp, xRbp);
  xPop(xRbp);
  codeByte(0xc3);
  return entry;
}
