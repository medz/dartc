import 'dart:ffi';

import '../../lib/layout/memory.dart';
import 'memory.dart';
import 'object_memory.dart';
import 'heap.dart';
import 'event_loop.dart';
import 'stack_frames.dart';

/// Walks the precise roots of stopped Dart frames, including native reentry.
final class NativeRoots(
  final int context,
  final ObjectAccess objects,
  final EventLoop events,
) implements RootSet {
  final StackFrames _frames = StackFrames(context);
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
    final global = Pointer<Int64>.fromAddress(
      context + RuntimeContext.globalRoots,
    ).value;
    if (global != 0) {
      objects.visitStrong(Memory.objectAt<Object>(global), visitor);
    }
    _frames.start(_entrySp, _entryPc);
    while (_frames.moveNext()) {
      final count = _frames.rootCount;
      for (var i = 0; i < count; i++) {
        visitor.visit(ObjectMemory.reference(_frames.rootSlot(i)));
      }
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
}
