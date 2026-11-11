import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'pointer_helpers.dart' show customMember;

@Export<Pointer<Int64> Function(Int64)>()
Pointer<Int64> fromAddress(int address) => .fromAddress(address);

@Export<Int64 Function(Pointer<Int64>)>()
int address(Pointer<Int64> pointer) => pointer.address;

@Export<Int64 Function(Pointer<Int64>)>()
int read(Pointer<Int64> pointer) => pointer.value;

@Export<Void Function(Pointer<Int64>, Int64)>()
void write(Pointer<Int64> pointer, int value) {
  pointer.value = value;
}

@Export<Int64 Function(Pointer<Int64>, Pointer<Int64>)>()
int equal(Pointer<Int64> left, Pointer<Int64> right) => left == right ? 1 : 0;

@Export<Pointer<Int64> Function(Pointer<Int64>, Pointer<Int64>, Int64)>()
Pointer<Int64> rotate(Pointer<Int64> left, Pointer<Int64> right, int count) {
  for (var i = 0; i < count; i++) {
    final previous = left;
    left = right;
    right = previous;
    write(left, read(left) + i);
  }
  return count < 0 ? right : left;
}

@Export<Int64 Function(Pointer<Int64>, Pointer<Int64>)>()
int update(Pointer<Int64> trace, Pointer<Int64> pointer) {
  final old = receiver(trace, pointer).value++;
  receiver(trace, pointer).value += operand(trace);
  return old;
}

Pointer<Int64> receiver(Pointer<Int64> trace, Pointer<Int64> pointer) {
  trace.value = trace.value * 10 + 1;
  return pointer;
}

int operand(Pointer<Int64> trace) {
  trace.value = trace.value * 10 + 2;
  return 7;
}

typedef MixedNative = Pointer<Int64> Function(
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
);
typedef MixedDart = Pointer<Int64> Function(
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
);

@Export<MixedNative>()
Pointer<Int64> mixed(
  Pointer<Int64> a,
  int b,
  Pointer<Int64> c,
  int d,
  Pointer<Int64> e,
  int f,
  Pointer<Int64> g,
  int h,
  Pointer<Int64> i,
  int j,
) {
  write(i, a.value + b + c.value + d + e.value + f + g.value + h + i.value + j);
  return g;
}

@Export<MixedNative>()
Pointer<Int64> forward(
  Pointer<Int64> a,
  int b,
  Pointer<Int64> c,
  int d,
  Pointer<Int64> e,
  int f,
  Pointer<Int64> g,
  int h,
  Pointer<Int64> i,
  int j,
) => mixed(i, j, g, h, e, f, c, d, a, b);

@Export<Int64 Function(Pointer<Int64>)>()
int declaredMember(Pointer<Int64> pointer) => customMember(pointer);

Pointer<T> exchangeSlot<T extends NativeType>(
  Pointer<Pointer<T>> slots,
  int index,
  Pointer<T> value,
) {
  final previous = slots[index];
  (slots + index).value = value;
  return previous;
}

@Export<
  Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64, Pointer<Int64>)
>()
Pointer<Int64> exchangePointer(
  Pointer<Pointer<Int64>> slots,
  int index,
  Pointer<Int64> value,
) => exchangeSlot(slots, index, value);

@Export<Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64)>()
Pointer<Int64> swapSlots(Pointer<Pointer<Int64>> slots, int index) {
  final first = slots.value;
  slots.value = slots[index];
  slots[index] = first;
  return slots.value;
}

@Export<
  Pointer<Pointer<Int64>> Function(Pointer<Pointer<Int64>>, Int64, Int64)
>()
Pointer<Pointer<Int64>> offsetSlots(
  Pointer<Pointer<Int64>> slots,
  int index,
  int operation,
) => switch (operation) {
  0 => slots + index,
  1 => slots - index,
  // ignore: deprecated_member_use
  _ => slots.elementAt(index),
};

typedef ReadPointer = Pointer<NativeFunction<Int64 Function(Pointer<Int64>)>>;

@Export<Int64 Function(Pointer<ReadPointer>, Pointer<Int64>)>()
int readThroughSlot(Pointer<ReadPointer> slots, Pointer<Int64> value) =>
    slots.value.asFunction<int Function(Pointer<Int64>)>()(value);

final class SlotNode(final Pointer<Int64> pointer, final SlotNode? previous);

@Export<Pointer<Int64> Function(Pointer<Pointer<Int64>>, Int64)>()
Pointer<Int64> retainSlot(Pointer<Pointer<Int64>> slots, int count) {
  var node = SlotNode(slots.value, null);
  for (var i = 0; i < count; i++) {
    node = SlotNode(slots[i % 2], node);
  }
  while (node.previous != null) {
    node = node.previous!;
  }
  return node.pointer;
}

void boundedWrite<I extends int, F extends double>(
  I address,
  I index,
  I integer,
  F floating,
) {
  final integers = Pointer<Int64>.fromAddress(address);
  integers.value = integer;
  integers[index] = integer;
  (integers + index).value = integer;
  (integers - index).value = integer;
  final doubles = Pointer<Double>.fromAddress(address);
  doubles.value = floating;
  doubles[index] = floating;
}
