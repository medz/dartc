import 'dart:ffi';

import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Walks suspended managed frames and native reentry segments without allocation.
final class StackFrames(final int context) {
  int _nextSp = 0, _nextPc = 0, _segment = 0, _record = 0;
  int _sp = 0, _pc = 0;

  int get pc => _pc;

  /// Immutable source-frame metadata, or zero for a generated machine frame.
  int get description =>
      Pointer<Int64>.fromAddress(_record + StackMapRecord.description).value;

  /// The managed continuation saved in this frame, if any.
  Object? get continuation {
    final offset = Pointer<Int64>.fromAddress(_record + StackMapRecord.context)
        .value;
    return offset == 0
        ? null
        : Memory.objectAt<Object?>(
            Pointer<Int64>.fromAddress(_sp + offset - 1).value,
          );
  }

  void start(int sp, int pc) {
    if (sp == 0 || pc == 0) Memory.fail();
    _nextSp = sp;
    _nextPc = pc;
    _segment = Pointer<Int64>.fromAddress(context + RuntimeContext.active)
        .value;
  }

  bool get isBoundary =>
      Pointer<Int64>.fromAddress(_record + StackMapRecord.callerStack).value ==
      0;
  int get rootCount =>
      Pointer<Int64>.fromAddress(_record + StackMapRecord.rootCount).value;
  int rootSlot(int index) =>
      _sp +
      Pointer<Int64>.fromAddress(_record + StackMapRecord.roots + index * 8)
          .value;

  bool moveNext() {
    if (_nextSp == 0) return false;
    _sp = _nextSp;
    _pc = _nextPc;
    _record = _find(pc);
    final caller = Pointer<Int64>.fromAddress(
      _record + StackMapRecord.callerStack,
    ).value;
    if (caller != 0) {
      _nextSp = _sp + caller;
      _nextPc = Pointer<Int64>.fromAddress(
        _sp +
            Pointer<Int64>.fromAddress(_record + StackMapRecord.returnAddress)
                .value,
      ).value;
    } else {
      _segment = _segment == 0
          ? 0
          : Pointer<Int64>.fromAddress(_segment + RuntimeContext.previousEntry)
                .value;
      _nextSp = _segment == 0
          ? 0
          : Pointer<Int64>.fromAddress(_segment + RuntimeContext.suspendedSp)
                .value;
      _nextPc = _segment == 0
          ? 0
          : Pointer<Int64>.fromAddress(_segment + RuntimeContext.suspendedPc)
                .value;
    }
    return true;
  }

  int _find(int pc) {
    final table = Pointer<Int64>.fromAddress(context + RuntimeContext.maps)
        .value;
    var low = 0,
        high = Pointer<Int64>.fromAddress(table + StackMapTable.count).value;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final entry =
          table + StackMapTable.entries + middle * StackMapTable.entrySize;
      final address = Pointer<Int64>.fromAddress(entry + StackMapTable.pc)
          .value;
      if (pc < address) {
        high = middle;
      } else if (pc > address) {
        low = middle + 1;
      } else {
        return table +
            Pointer<Int64>.fromAddress(entry + StackMapTable.record).value;
      }
    }
    Memory.fail();
  }
}
