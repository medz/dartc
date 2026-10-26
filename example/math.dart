import 'dart:ffi';

typedef AddNative = Int64 Function(Int64, Int64);

int addImpl(int a, int b) => a + b;

final add = Pointer.fromFunction<AddNative>(addImpl, 0);
