import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'output.dart';
import 'statics.dart';
import 'system.dart';

/// Lowers the operations of the runtime.
final class MachineLowering(
  final StaticData _statics,
  final OutputData _output, {
  required final bool collectsAlways,
}) {
  /// Adds [op] to [block], returning its result if it has one.
  LirValue? lower(LirBlock block, HirMachineOp op, List<LirValue> arguments) {
    LirValue number(int value) => block.add(ConstInt(value));
    LirValue address() => block.add(Convert(.intToPtr, arguments[0]));
    LirValue load(Width width) => block.add(Load(width, address()));
    LirValue symbol(String name) =>
        block.add(Convert(.ptrToInt, block.add(SymbolAddress(name))));
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
      case .writeError:
        _output.writeByte(block, standardError, arguments.single);
        return null;
      case .resume:
        final [frame, code, exception, trace] = arguments;
        block.add(Resume(frame, code, exception, trace));
        return null;
      case .handlers:
        return symbol(handlerSymbol);
      case .trap:
        // Code never continues after it.
        return null;
      case .frameAddress:
        return block.add(FrameAddress());
      case .codeStart:
        return symbol(textSymbol);
      case .stackMaps:
        return symbol(stackMapSymbol);
      case .classTable:
        return symbol(classTableSymbol);
      case .globalRoots:
        return block.add(
          IntBinary(.add, symbol(globalsSymbol), number(firstGlobal)),
        );
      case .globalRootCount:
        return number(_statics.rootCount);
      case .collectsAlways:
        return number(collectsAlways ? 1 : 0);
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
