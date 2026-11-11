import '../../layout/memory.dart';
import 'memory.dart';
import 'object_memory.dart';
import 'heap.dart';

/// Walks the precise roots of stopped Dart frames, including native reentry.
final class NativeRoots(final int context, final ObjectAccess objects)
    implements RootSet {
  int _entrySp = 0, _entryPc = 0;
  bool _stopped = false, _closed = false;
  int _table = 0;
  int _sp = 0;
  int _pc = 0;
  int _segment = 0;
  int _record = 0;
  int _index = 0;
  bool _done = true;
  int current = 0;

  void publish(int sp, int pc) {
    if (_stopped || _closed) Memory.fail();
    _entrySp = sp;
    _entryPc = pc;
  }

  @override
  bool stop() {
    if (_stopped || _closed || _entrySp == 0 || _entryPc == 0) Memory.fail();
    _stopped = true;
    _reset();
    return true;
  }

  @override
  void visit(ReferenceVisitor visitor) {
    if (!_stopped) Memory.fail();
    final global = Memory.read(context + RuntimeContext.globalRoots);
    if (global != 0) {
      objects.visitStrong(Memory.objectAt<Object>(global), visitor);
    }
    while (moveNext()) {
      visitor.visit(ObjectMemory.reference(current));
    }
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

  void _reset() {
    _table = Memory.read(context + RuntimeContext.maps);
    _segment = Memory.read(context + RuntimeContext.active);
    _sp = _entrySp;
    _pc = _entryPc;
    _record = 0;
    _index = 0;
    _done = false;
  }

  bool moveNext() {
    while (!_done) {
      if (_record == 0) _record = _findFrame();
      if (_index < Memory.read(_record + 24)) {
        current = _sp + Memory.read(_record + 32 + _index * 8);
        _index++;
        return true;
      }
      final caller = Memory.read(_record + 8);
      if (caller != 0) {
        _pc = Memory.read(_sp + Memory.read(_record + 16));
        _sp += caller;
      } else {
        _segment = _segment == 0
            ? 0
            : Memory.read(_segment + RuntimeContext.previousEntry);
        if (_segment == 0) {
          _done = true;
          return false;
        }
        _sp = Memory.read(_segment + RuntimeContext.suspendedSp);
        _pc = Memory.read(_segment + RuntimeContext.suspendedPc);
        if (_sp == 0 || _pc == 0) Memory.fail();
      }
      _record = 0;
      _index = 0;
    }
    return false;
  }

  int _findFrame() {
    final count = Memory.read(_table);
    var record = _table + 8;
    for (var i = 0; i < count; i++) {
      if (Memory.read(record) == _pc) return record;
      record += 32 + Memory.read(record + 24) * 8;
    }
    Memory.fail();
  }
}
