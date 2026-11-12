import '../../lib/layout/memory.dart';
import 'memory.dart';
import 'object_memory.dart';
import 'heap.dart';
import 'event_loop.dart';

/// Walks the precise roots of stopped Dart frames, including native reentry.
final class NativeRoots(
  final int context,
  final ObjectAccess objects,
  final EventLoop events,
) implements RootSet {
  int _entrySp = 0, _entryPc = 0;
  bool _stopped = false, _closed = false;

  void publish(int sp, int pc) {
    if (_stopped || _closed) Memory.fail();
    _entrySp = sp;
    _entryPc = pc;
  }

  @override
  bool stop() {
    if (_stopped || _closed || _entrySp == 0 || _entryPc == 0) Memory.fail();
    _stopped = true;
    return true;
  }

  @override
  void visit(ReferenceVisitor visitor) {
    if (!_stopped) Memory.fail();
    events.visitRoots(visitor);
    final global = Memory.read(context + RuntimeContext.globalRoots);
    if (global != 0) {
      objects.visitStrong(Memory.objectAt<Object>(global), visitor);
    }
    final table = Memory.read(context + RuntimeContext.maps);
    var segment = Memory.read(context + RuntimeContext.active);
    var sp = _entrySp, pc = _entryPc;
    while (sp != 0 && pc != 0) {
      final record = _findFrame(table, pc);
      final count = Memory.read(record + 24);
      for (var i = 0; i < count; i++) {
        final slot = sp + Memory.read(record + 32 + i * 8);
        visitor.visit(ObjectMemory.reference(slot));
      }
      final caller = Memory.read(record + 8);
      if (caller != 0) {
        pc = Memory.read(sp + Memory.read(record + 16));
        sp += caller;
      } else {
        segment = segment == 0
            ? 0
            : Memory.read(segment + RuntimeContext.previousEntry);
        if (segment == 0) return;
        sp = Memory.read(segment + RuntimeContext.suspendedSp);
        pc = Memory.read(segment + RuntimeContext.suspendedPc);
      }
    }
    Memory.fail();
  }

  @override
  void resume() {
    if (!_stopped || _closed) Memory.fail();
    _stopped = false;
  }

  @override
  void close() {
    if (_stopped) Memory.fail();
    _closed = true;
  }

  int _findFrame(int table, int pc) {
    final count = Memory.read(table);
    var record = table + 8;
    for (var i = 0; i < count; i++) {
      if (Memory.read(record) == pc) return record;
      record += 32 + Memory.read(record + 24) * 8;
    }
    Memory.fail();
  }
}
