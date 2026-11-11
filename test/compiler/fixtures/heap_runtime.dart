import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/src/runtime/heap.dart';

@Export<Int64 Function(Int64, Int64)>()
int capacity(int current, int needed) => heapCapacity(current, needed);

@Export<Void Function(Pointer<Int64>, Pointer<Int64>, Int64)>()
void copy(Pointer<Int64> destination, Pointer<Int64> source, int words) =>
    copyWords(destination, source, words);

@Export<Void Function(Pointer<Int64>, Int64)>()
void clear(Pointer<Int64> destination, int words) =>
    clearWords(destination, words);

T identity<T>(T value) => value;

@Export<Void Function(Pointer<Int64>, Pointer<Int64>, Int64)>()
void copyThroughValue(
  Pointer<Int64> destination,
  Pointer<Int64> source,
  int words,
) {
  final action = identity(copyWords);
  action(destination, source, words);
}
