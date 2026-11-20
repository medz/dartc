import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'memory.dart';
import 'object_memory.dart';
import 'heap.dart';
import 'control.dart';
import 'module_roots.dart';
import 'stack_frames.dart';

/// Walks the precise roots of stopped Dart frames, including native reentry.
final class NativeRoots(final int context, final ObjectAccess objects)
    implements RootSet {
  /// Links a live entry record before executing Dart in [context].
  ///
  /// The caller supplies aligned, live context storage and a fresh record that
  /// overlaps neither the context nor any still-active entry record. The record
  /// must remain live through event draining and heap release, until [unlink].
  /// [maps] is this module's linked stack table. [globalRoots] is its immutable
  /// [ModuleRootTable] address, or zero for an empty registry.
  @RuntimeEntry(.linkEntry)
  @NonAllocating()
  static void link(int context, int record, int maps, int globalRoots) {
    final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase)
        .value;
    if (phase != RuntimePhase.dormant && phase != RuntimePhase.managed) {
      Memory.fail();
    }
    Pointer<Int64>.fromAddress(record + RuntimeContext.previousEntry)
        .value = Pointer<Int64>.fromAddress(context + RuntimeContext.active)
        .value;
    Pointer<Int64>.fromAddress(record + RuntimeContext.suspendedSp).value = 0;
    Pointer<Int64>.fromAddress(record + RuntimeContext.suspendedPc).value = 0;
    Pointer<Int64>.fromAddress(context + RuntimeContext.active).value = record;
    Pointer<Int64>.fromAddress(context + RuntimeContext.maps).value = maps;
    Pointer<Int64>.fromAddress(context + RuntimeContext.globalRoots).value =
        globalRoots;
  }

  /// Removes the innermost record after all work using its roots has finished.
  ///
  /// Heap release may have returned [context] to its dormant phase. Module
  /// metadata remains installed, and the caller may then release [record].
  @RuntimeEntry(.unlinkEntry)
  @NonAllocating()
  static void unlink(int context, int record) {
    if (Pointer<Int64>.fromAddress(context + RuntimeContext.active).value !=
        record) {
      Memory.fail();
    }
    Pointer<Int64>.fromAddress(context + RuntimeContext.active)
        .value = Pointer<Int64>.fromAddress(
      record + RuntimeContext.previousEntry,
    ).value;
  }

  final StackFrames _frames = StackFrames(context);
  final ControlObjects _control = ControlObjects(context, objects);
  final ModuleRoots _modules = ModuleRoots(context);
  int _entrySp = 0, _entryPc = 0;

  int get _phase =>
      Pointer<Int64>.fromAddress(context + RuntimeContext.phase).value;
  set _phase(int value) =>
      Pointer<Int64>.fromAddress(context + RuntimeContext.phase).value = value;

  @NonAllocating()
  void publish(int sp, int pc) {
    if (_phase != RuntimePhase.managed || sp == 0 || pc == 0) {
      objects.corruptHeap();
    }
    _entrySp = sp;
    _entryPc = pc;
  }

  @override
  @NonAllocating()
  bool stop() {
    if (_phase != RuntimePhase.managed || _entrySp == 0 || _entryPc == 0) {
      objects.corruptHeap();
    }
    _phase = RuntimePhase.collecting;
    return true;
  }

  @override
  void visit(ReferenceVisitor visitor) {
    if (_phase != RuntimePhase.collecting) objects.corruptHeap();
    _control.start();
    while (_control.moveNext()) {
      objects.visitStrong(Memory.objectAt<Object>(_control.address), visitor);
    }
    _modules.start();
    while (true) {
      final address = _modules.nextAddress();
      if (address == 0) break;
      objects.visitStrong(Memory.objectAt<Object>(address), visitor);
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
  void traceConditional(Liveness live, ReferenceVisitor visitor) {
    if (_phase != RuntimePhase.collecting) objects.corruptHeap();
    _control.start();
    while (_control.moveNext()) {
      objects.traceConditional(
        Memory.objectAt<Object>(_control.address),
        live,
        visitor,
      );
    }
    _modules.start();
    while (true) {
      final address = _modules.nextAddress();
      if (address == 0) break;
      objects.traceConditional(Memory.objectAt<Object>(address), live, visitor);
    }
  }

  @override
  void clearWeak(Liveness live) {
    if (_phase != RuntimePhase.collecting) objects.corruptHeap();
    _control.start();
    while (_control.moveNext()) {
      objects.clearWeak(Memory.objectAt<Object>(_control.address), live);
    }
    _modules.start();
    while (true) {
      final address = _modules.nextAddress();
      if (address == 0) break;
      objects.clearWeak(Memory.objectAt<Object>(address), live);
    }
  }

  @override
  @NonAllocating()
  void resume() {
    if (_phase != RuntimePhase.collecting) objects.corruptHeap();
    _phase = RuntimePhase.managed;
  }

  @override
  @NonAllocating()
  void close() {
    if (_phase == RuntimePhase.closed) return;
    if (_phase != RuntimePhase.managed) objects.corruptHeap();
    _phase = RuntimePhase.closed;
  }
}
