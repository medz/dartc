import 'dart:ffi';
import 'package:dartc/interop.dart';

final class Witness() implements Finalizable {}

final class Node(final int value, final Node? next);

Node? head;

@Export<Void Function(Pointer<NativeFinalizerFunction>, Pointer<Int64>)>()
void registerWitness(Pointer<NativeFinalizerFunction> callback, Pointer<Int64> counter) {
  NativeFinalizer(callback).attach(Witness(), counter.cast(), externalSize: 1 << 24);
}

@Export<Int64 Function(Int64, Pointer<Int64>)>()
int grow(int count, Pointer<Int64> counter) {
  for (var i = 0; i < count; i++) {
    head = Node(i, head);
  }
  return counter.value;
}

@Export<Int64 Function(Int64)>()
int read(int index) {
  var node = head;
  while (index > 0 && node != null) {
    node = node.next;
    index--;
  }
  return node?.value ?? -1;
}
