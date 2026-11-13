import 'dart:ffi';

int valid() => 1;

void unused(int Function(int) callback) {
  Pointer.fromFunction<Int64 Function(Int64)>(callback, -1);
}
