import 'dart:ffi';

T identity<T>(T value) => value;
int valid() => 1;

void unused() {
  Pointer.fromFunction<Int64 Function(Int64)>(identity<int>, -1);
}
