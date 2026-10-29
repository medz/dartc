import 'exports.dart';
import 'host.dart';
import 'machine.dart';
import 'nogc.dart';
import 'source.dart';
import 'ssa.dart';
import 'types.dart';

Never _libraryError(String symbol, String message) {
  print(
    (symbol.isEmpty ? 'Library output' : 'Export ' + symbol) + ': ' + message,
  );
  hostExit(1);
}

int libraryTypeSize(int type) => switch (ffiKind(type)) {
  ffiInt8 || ffiUint8 || ffiBool => 1,
  ffiInt16 || ffiUint16 => 2,
  ffiInt32 || ffiUint32 || ffiFloat => 4,
  ffiInt64 ||
  ffiUint64 ||
  ffiIntPtr ||
  ffiUintPtr ||
  ffiDouble ||
  ffiPointer => 8,
  _ => _libraryError('', 'native type has no implemented target layout'),
};

bool _wordType(int type) => switch (ffiKind(type)) {
  ffiInt64 || ffiUint64 || ffiIntPtr || ffiUintPtr || ffiPointer => true,
  _ => false,
};

// These signatures already use the internal word calling convention.
bool libraryDirectCall(int type) {
  final signature = functionSignature(type);
  if (ffiKind(signature.result) != ffiVoid && !_wordType(signature.result))
    return false;
  for (final parameter in signature.parameters)
    if (!_wordType(parameter)) return false;
  return true;
}

void checkLibraryExports(
  List<SsaFunction> ssa,
  List<MachineFunction> program,
  SourceProgram sources,
) {
  final reachable = <int>[];
  for (final function in program) reachable.add(function.reachable ? 1 : 0);
  final obligations = checkNoGcSsa(ssa, sources, reachable);
  final effects = checkNoGcMachine(program, obligations, sources, reachable);
  for (final declaration in checkedExports) {
    final function = declaration.function;
    if (function < 0) {
      if (declaration.constantBits == null)
        _libraryError(
          declaration.symbol,
          'mutable data requires a runtime boundary',
        );
      libraryTypeSize(declaration.signature);
      continue;
    }
    if ((effects[function] & ~(ssaRead | ssaWrite | ssaNative)) != 0)
      _libraryError(
        declaration.symbol,
        'reachable code requires a managed exception or allocation boundary',
      );
  }
  for (var f = 0; f < program.length; f++) {
    if (!program[f].reachable) continue;
    for (final block in program[f].blocks) {
      for (final instruction in block.instructions) {
        if (instruction.op == mAddress)
          _libraryError(
            '',
            'reachable code requires runtime data or a managed context',
          );
      }
    }
  }
}

int _roundedShift(int value, int shift) {
  final truncated = value >>> shift;
  final remainder = value & ((1 << shift) - 1);
  final half = 1 << (shift - 1);
  return truncated +
      (remainder > half || remainder == half && (truncated & 1) != 0 ? 1 : 0);
}

// Narrow only the exported copy. The Dart constant retains its original value.
int libraryConstantBits(CheckedExport declaration) {
  final bits = declaration.constantBits!;
  if (ffiKind(declaration.signature) != ffiFloat) return bits;
  final sign = (bits >>> 32) & 0x80000000;
  final exponent = (bits >>> 52) & 0x7ff;
  final fraction = bits & 0xfffffffffffff;
  if (exponent == 0x7ff)
    return sign |
        0x7f800000 |
        (fraction == 0 ? 0 : (fraction >>> 29) | 0x400000);
  if (exponent > 1150) return sign | 0x7f800000;
  if (exponent < 873) return sign;
  final significand = (1 << 52) | fraction;
  if (exponent < 897) return sign | _roundedShift(significand, 926 - exponent);
  return sign | (((exponent - 897) << 23) + _roundedShift(significand, 29));
}
