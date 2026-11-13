import 'dart:ffi';

NativeCallable<Int64 Function(Int64)> unused(int fallback) =>
    NativeCallable<Int64 Function(Int64)>.isolateLocal(
      (int value) => value,
      exceptionalReturn: fallback,
    );

int answer() => 42;
