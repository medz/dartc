import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'dispatch.dart';
import 'output.dart';
import 'statics.dart';
import 'system.dart';

/// Lowers the operations of the runtime.
final class MachineLowering(
  final StaticData _statics, {
  required final bool collectsAlways,
}) {
  /// Whether the program writes to files.
  bool writesOutput = false;

  /// Whether it uses the arguments at [argumentsSymbol].
  bool usesArguments = false;

  /// Whether it uses the buffer at [bufferSymbol].
  bool usesBuffer = false;

  /// What some give the addresses of.
  static const _symbols = <HirMachineOp, String>{
    .handlers: handlerSymbol,
    .codeStart: textSymbol,
    .stackMaps: stackMapSymbol,
    .classTable: classTableSymbol,
  };

  /// The functions of the C library that do the work of some.
  static const _functions = <HirMachineOp, String>{
    .sine: 'sin',
    .cosine: 'cos',
    .tangent: 'tan',
    .arcSine: 'asin',
    .arcCosine: 'acos',
    .arcTangent: 'atan',
    .exponential: 'exp',
    .logarithm: 'log',
    .arcTangent2: 'atan2',
    .power: 'pow',
  };

  /// Adds [op] to [block], returning its result if it has one.
  LirValue? lower(LirBlock block, HirMachineOp op, List<LirValue> arguments) {
    LirValue number(int value) => block.add(ConstInt(value));
    LirValue address() => block.add(Convert(.intToPtr, arguments[0]));
    LirValue load(Width width) => block.add(Load(width, address()));
    LirValue symbol(String name) =>
        block.add(Convert(.ptrToInt, block.add(SymbolAddress(name))));
    if (_symbols[op] case final name?) return symbol(name);
    if (_functions[op] case final name?) {
      return block.add(callSystem(name, arguments));
    }
    switch (op) {
      case .load64:
        return load(.i64);
      case .load32:
        return load(.u32);
      case .load32Signed:
        return load(.i32);
      case .store64:
        block.add(Store(.i64, address(), arguments[1]));
        return null;
      case .store32:
        block.add(Store(.u32, address(), arguments[1]));
        return null;
      case .mapMemory:
        return _map(block, arguments.single);
      case .unmapMemory:
        block.add(callSystem('munmap', arguments));
        return null;
      case .outputBuffer:
        usesBuffer = true;
        return symbol(bufferSymbol);
      case .load8:
        return load(.u8);
      case .store8:
        block.add(Store(.u8, address(), arguments[1]));
        return null;
      case .write:
        writesOutput = true;
        final [file, from, count] = arguments;
        final start = block.add(Convert(.intToPtr, from));
        block.add(Call(writeSymbol, writeSignature, [file, start, count]));
        return null;
      case .formatDouble:
        final [value, digits, to] = arguments;
        final start = block.add(Convert(.intToPtr, to));
        block.add(callSystem('gcvt', [value, digits, start]));
        return null;
      case .parseDouble:
        final none = block.add(Convert(.intToPtr, number(0)));
        return block.add(callSystem('strtod', [address(), none]));
      case .arguments:
        usesArguments = true;
        return symbol(argumentsSymbol);
      case .realTime || .steadyTime || .localTime || .randomBits || .pause:
        return _system(block, op, arguments);
      case .classNumber:
        return block.add(Load(.u32, arguments.single, offset: classOffset));
      case .addressOf:
        return block.add(Convert(.refToInt, arguments.single));
      case .resume:
        final [frame, code, exception, trace] = arguments;
        block.add(Resume(frame, code, exception, trace));
        return null;
      case .isSame:
        return block.add(Compare(.eq, arguments[0], arguments[1]));
      case .trap:
        // Code never continues after it.
        return null;
      case .frameAddress:
        return block.add(FrameAddress());
      case .globalRoots:
        return block.add(
          IntBinary(.add, symbol(globalsSymbol), number(firstGlobal)),
        );
      case .globalRootCount:
        return number(_statics.rootCount);
      case .collectsAlways:
        return number(collectsAlways ? 1 : 0);
      default:
        throw StateError('No code for ${op.name}.');
    }
  }

  /// Asks the system for times and random bits.
  static LirValue? _system(
    LirBlock block,
    HirMachineOp op,
    List<LirValue> arguments,
  ) {
    LirValue number(int value) => block.add(ConstInt(value));
    switch (op) {
      case .realTime:
        return block.add(callSystem('clock_gettime_nsec_np', [number(0)]));
      case .steadyTime:
        return block.add(callSystem('clock_gettime_nsec_np', [number(8)]));
      case .localTime:
        final from = block.add(Convert(.intToPtr, arguments.single));
        final to = block.add(PtrAdd(from, number(8)));
        block.add(callSystem('localtime_r', [from, to]));
        return null;
      case .pause:
        block.add(callSystem('usleep', arguments));
        return null;
      default:
        final bits = block.add(callSystem('arc4random', []));
        return block.add(IntBinary(.and, bits, number(0xffffffff)));
    }
  }

  /// Private, anonymous memory that can be read and written, or 0.
  static LirValue _map(LirBlock block, LirValue bytes) {
    const readWrite = 3, privateAnonymous = 0x1002, failed = -1;
    LirValue number(int value) => block.add(ConstInt(value));
    final found = block.add(
      callSystem('mmap', [
        number(0),
        bytes,
        number(readWrite),
        number(privateAnonymous),
        number(-1),
        number(0),
      ]),
    );
    final hasFailed = block.add(Compare(.eq, found, number(failed)));
    // All bits where it succeeded, none where it failed.
    final mask = block.add(IntBinary(.sub, hasFailed, number(1)));
    return block.add(IntBinary(.and, found, mask));
  }
}
