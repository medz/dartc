import 'dart:ffi';

final class Allocation() extends Struct {
  @Uint8()
  external int tag;
  @Double()
  external double value;
  external Pointer<Int64> next;
}

final class Choice() extends Union {
  @Int64()
  external int integer;
  @Double()
  external double floating;
}

final class NativeAllocator() implements Allocator {
  final _library = DynamicLibrary.process();
  late final _malloc = _library
      .lookupFunction<
        Pointer<Void> Function(Size),
        Pointer<Void> Function(int)
      >('malloc');
  late final _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  int bytes = 0, live = 0, order = 0;
  Type? allocatedType;

  @override
  Pointer<T> allocate<T extends NativeType>(
    int byteCount, {
    int? alignment = 16,
  }) {
    order = order * 10 + 3;
    bytes = byteCount;
    allocatedType = T;
    if (byteCount < 0 || alignment != 16) throw ArgumentError(byteCount);
    if (byteCount == 0) return nullptr.cast<T>();
    final pointer = _malloc(byteCount);
    if (pointer == nullptr) throw ArgumentError(byteCount);
    live++;
    return pointer.cast<T>();
  }

  @override
  void free(Pointer pointer) {
    if (pointer == nullptr) return;
    _free(pointer.cast<Void>());
    live--;
  }
}

void check(bool value) {
  if (!value) throw StateError('Allocator contract');
}

Allocator receiver(NativeAllocator allocator) {
  allocator.order = allocator.order * 10 + 1;
  return allocator;
}

int count(NativeAllocator allocator) {
  allocator.order = allocator.order * 10 + 2;
  return 3;
}

Allocator? absent;

void main() {
  final state = NativeAllocator();
  Allocator allocator = state;
  final values = receiver(state)<Double>(count(state));
  try {
    check(state.order == 123 && state.bytes == 24);
    check(state.allocatedType == Double);
    values[0] = 1.25;
    values[1] = -2.5;
    values[2] = values[0] + values[1];
    check(values[2] == -1.25);
  } finally {
    allocator.free(values);
  }
  final record = allocator.call<Allocation>();
  try {
    check(state.bytes == sizeOf<Allocation>());
    record.ref.tag = 7;
    record.ref.value = 1.5;
    record.ref.next = nullptr;
    check(record.ref.tag == 7 && record.ref.value == 1.5);
    check(record.ref.next == nullptr);
  } finally {
    allocator.free(record);
  }
  final union = AllocatorAlloc(allocator).call<Choice>();
  try {
    check(state.bytes == sizeOf<Choice>());
    union.ref.floating = 1.0;
    check(union.ref.integer == 0x3ff0000000000000);
  } finally {
    allocator.free(union);
  }
  final pointers = allocator<Pointer<Allocation>>(2);
  try {
    check(state.bytes == sizeOf<Pointer<Allocation>>() * 2);
    pointers[0] = nullptr;
    pointers[1] = pointers[0];
    check(pointers[1] == nullptr);
  } finally {
    allocator.free(pointers);
  }
  final sizes = allocator<Size>(2);
  try {
    check(state.bytes == sizeOf<Size>() * 2);
    sizes[0] = 37;
    sizes[1] = sizes[0] + 5;
    check(sizes[1] == 42);
  } finally {
    allocator.free(sizes);
  }
  check(allocator<Int8>(0) == nullptr && state.bytes == 0);
  try {
    allocator<Int16>(-3);
    throw StateError('Missing allocator failure');
  } on ArgumentError {
    check(state.bytes == -6);
  }
  state.order = 0;
  check(absent?.call<Double>(count(state)) == null && state.order == 0);
  check(state.live == 0);
  print('allocators: ok');
}
