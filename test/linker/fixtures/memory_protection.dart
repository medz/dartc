import 'dart:ffi';
import 'dart:io';

int memoryProtection(Pointer pointer) {
  final address = pointer.address;
  if (Platform.isLinux) {
    for (final line in File('/proc/self/maps').readAsLinesSync()) {
      final fields = line.split(' '), range = fields[0].split('-');
      if (address < int.parse(range[0], radix: 16) ||
          address >= int.parse(range[1], radix: 16)) {
        continue;
      }
      final flags = fields[1];
      return (flags[0] == 'r' ? 1 : 0) |
          (flags[1] == 'w' ? 2 : 0) |
          (flags[2] == 'x' ? 4 : 0);
    }
    throw StateError('No mapping for $address.');
  }
  if (!Platform.isMacOS) throw UnsupportedError('Memory protection query.');
  final system = DynamicLibrary.process();
  final allocate = system
      .lookupFunction<
        Pointer<Uint8> Function(Size, Size),
        Pointer<Uint8> Function(int, int)
      >('calloc');
  final free = system
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  final region = system
      .lookupFunction<
        Int32 Function(
          Uint32,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Int32,
          Pointer<Int32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          int,
          Pointer<Int32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('mach_vm_region');
  final deallocate = system
      .lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>(
        'mach_port_deallocate',
      );
  final task = system.lookup<Uint32>('mach_task_self_').value;
  final memory = allocate(1, 64);
  if (memory == nullptr) throw StateError('Memory query allocation failed.');
  final location = memory.cast<Uint64>();
  final size = (memory + 8).cast<Uint64>();
  final count = (memory + 16).cast<Uint32>();
  final object = (memory + 20).cast<Uint32>();
  final info = (memory + 24).cast<Int32>();
  try {
    location.value = address;
    count.value = 9; // VM_REGION_BASIC_INFO_64 contains nine 32-bit words.
    final result = region(task, location, size, 9, info, count, object);
    if (result != 0 ||
        location.value > address ||
        address - location.value >= size.value) {
      throw StateError('mach_vm_region failed for $address: $result');
    }
    return info.value;
  } finally {
    if (object.value != 0) deallocate(task, object.value);
    free(memory);
  }
}
