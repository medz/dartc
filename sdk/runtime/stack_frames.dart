import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Walks suspended managed frames and native reentry segments without allocation.
final class StackFrames(final int context) {
  int _nextSp = 0, _nextPc = 0, _segment = 0, _record = 0;
  int _sp = 0, _pc = 0;

  int get pc => _pc;

  /// The source frame description, or `null` for a generated machine frame.
  String? get description {
    final address = Memory.read(_record + StackMapRecord.description);
    return address == 0 ? null : Memory.objectAt<String>(address);
  }

  void start(int sp, int pc) {
    if (sp == 0 || pc == 0) Memory.fail();
    _nextSp = sp;
    _nextPc = pc;
    _segment = Memory.read(context + RuntimeContext.active);
  }

  bool get isBoundary => Memory.read(_record + StackMapRecord.callerStack) == 0;
  int get rootCount => Memory.read(_record + StackMapRecord.rootCount);
  int rootSlot(int index) =>
      _sp + Memory.read(_record + StackMapRecord.roots + index * 8);

  bool moveNext() {
    if (_nextSp == 0) return false;
    _sp = _nextSp;
    _pc = _nextPc;
    _record = _find(pc);
    final caller = Memory.read(_record + StackMapRecord.callerStack);
    if (caller != 0) {
      _nextSp = _sp + caller;
      _nextPc = Memory.read(
        _sp + Memory.read(_record + StackMapRecord.returnAddress),
      );
    } else {
      _segment = _segment == 0
          ? 0
          : Memory.read(_segment + RuntimeContext.previousEntry);
      _nextSp = _segment == 0
          ? 0
          : Memory.read(_segment + RuntimeContext.suspendedSp);
      _nextPc = _segment == 0
          ? 0
          : Memory.read(_segment + RuntimeContext.suspendedPc);
    }
    return true;
  }

  int _find(int pc) {
    final table = Memory.read(context + RuntimeContext.maps);
    final count = Memory.read(table);
    var record = table + StackMapRecord.tableHeader;
    for (var i = 0; i < count; i++) {
      if (Memory.read(record + StackMapRecord.pc) == pc) return record;
      record +=
          StackMapRecord.roots +
          Memory.read(record + StackMapRecord.rootCount) * 8;
    }
    Memory.fail();
  }
}
