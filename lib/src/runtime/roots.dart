import '../../layout/memory.dart';
import 'memory.dart';

/// Walks the precise roots of stopped Dart frames, including native reentry.
final class RootSlots() {
  int _table = 0;
  int _sp = 0;
  int _pc = 0;
  int _segment = 0;
  int _record = 0;
  int _index = 0;
  bool _done = true;
  int current = 0;

  void reset(int context, int sp, int pc) {
    _table = Memory.read(context + RuntimeContext.maps);
    _segment = Memory.read(context + RuntimeContext.active);
    _sp = sp;
    _pc = pc;
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
