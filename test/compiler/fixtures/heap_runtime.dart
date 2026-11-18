import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/layout/memory.dart';

import '../../../sdk/runtime/allocator.dart';
// This library exists in the compiler's supplied source resource graph.
// Use its actual identity so this low-level fixture reaches the trusted leaf.
// ignore: uri_does_not_exist
import '/__dartc__/sdk/runtime/memory.dart' as runtime;
// ignore: uri_does_not_exist
import '/__dartc__/sdk/runtime/control.dart' as control;

@Export<Int64 Function(Int64)>()
int capacity(int needed) => slotSize(needed);

final class Cell(final int value, [final Cell? next]);

final class ControlHolder(
  Cell? strong,
  final WeakReference<Cell> weak,
  int Function()? read,
) {
  Cell? strong = strong;
  int Function()? read = read;
}

ControlHolder? _control;
WeakReference<Cell>? _collectionWitness, _strongWitness;
Cell? _pressure;
final class PendingControl(
  final Cell strong,
  final Cell weak,
  final int Function() read,
);
PendingControl? _pending;

@Export<Void Function(Int64)>()
void createManaged(int value) {
  final strong = Cell(value), weak = Cell(value + 1);
  _collectionWitness = WeakReference(Cell(value + 2));
  _strongWitness = WeakReference(strong);
  int read() => strong.value;
  _pending = PendingControl(strong, weak, read);
}

@Export<Void Function()>()
void createControl() {
  final pending = _pending!;
  final phase = Pointer<Int64>.fromAddress(
    runtime.Memory.context() + RuntimeContext.phase,
  );
  final previous = phase.value;
  phase.value = RuntimePhase.control;
  try {
    _control = ControlHolder(
      pending.strong,
      WeakReference(pending.weak),
      pending.read,
    );
  } finally {
    phase.value = previous;
  }
  _pending = null;
}

bool managed(Object value) =>
    Pointer<Int64>.fromAddress(
      runtime.Memory.addressOf(value) + ObjectHeader.pageOffset,
    ).value !=
    0;

@Export<Int64 Function()>()
int controlPlacement() =>
    (managed(_control!) ? 1 : 0) |
    (managed(_control!.weak) ? 2 : 0) |
    (managed(_control!.strong!) ? 4 : 0) |
    (managed(_control!.read!) ? 8 : 0);

@Export<Int64 Function(Int64)>()
int collectPressure(int count) {
  Cell? next;
  for (var i = 0; i < count; i++) {
    next = Cell(i, next);
  }
  _pressure = next;
  var sum = 0;
  for (var cell = _pressure; cell != null; cell = cell.next) {
    sum += cell.value;
  }
  return sum;
}

@Export<Int64 Function()>()
int controlStatus() {
  final holder = _control!;
  return (_collectionWitness!.target == null ? 1 : 0) |
      (holder.weak.target == null ? 2 : 0) |
      (_strongWitness!.target != null ? 4 : 0) |
      (identical(holder.strong, _strongWitness!.target) ? 8 : 0);
}

@Export<Int64 Function()>()
int readControl() => _control!.strong!.value + _control!.read!();

@Export<Void Function()>()
void clearControl() {
  _control!.strong = null;
  _control!.read = null;
  _pressure = null;
  _collectionWitness = WeakReference(Cell(-1));
}

@Export<Int64 Function()>()
int phaseContext() => runtime.Memory.context();

@Export<Int64 Function()>()
int pressureValue() => _pressure?.value ?? -1;

@Export<Void Function(Int64)>()
void allocateInPhase(int value) {
  final phase = Pointer<Int64>.fromAddress(
    runtime.Memory.context() + RuntimeContext.phase,
  );
  phase.value = value;
  _pressure = Cell(value, _pressure);
  phase.value = RuntimePhase.managed;
}

@Export<Void Function(Int64)>()
void controlInPhase(int value) {
  final cell = Cell(97);
  final address = runtime.Memory.addressOf(cell);
  final descriptor = Pointer<Int64>.fromAddress(
    address + ObjectHeader.descriptorOffset,
  ).value;
  final bytes = Pointer<Int64>.fromAddress(address + ObjectHeader.sizeOffset)
      .value;
  final context = runtime.Memory.context();
  final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase);
  phase.value = value;
  control.allocateControl(context, descriptor, bytes);
  phase.value = RuntimePhase.managed;
}
