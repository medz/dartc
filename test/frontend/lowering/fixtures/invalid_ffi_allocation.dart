import 'dart:ffi';

Pointer<T> allocate<T extends SizedNativeType>(Allocator allocator) =>
    allocator<T>();

Pointer<T> explicit<T extends SizedNativeType>(Allocator allocator) =>
    allocator.call<T>();
