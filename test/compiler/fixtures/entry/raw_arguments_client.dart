import 'dart:convert';
import 'dart:ffi';

void main(List<String> arguments) {
  final process = DynamicLibrary.process();
  final malloc = process
      .lookupFunction<
        Pointer<Void> Function(Size),
        Pointer<Void> Function(int)
      >('malloc');
  final free = process
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  final execv = process
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>),
        int Function(Pointer<Uint8>, Pointer<Pointer<Uint8>>)
      >('execv');
  final storage = <Pointer<Void>>[];
  Pointer<Void> allocate(int bytes) {
    final address = malloc(bytes);
    if (address.address == 0) throw StateError('malloc failed');
    storage.add(address);
    return address;
  }

  try {
    final bytes = <List<int>>[
      for (final argument in arguments) utf8.encode(argument),
      [0x61, 0xff, 0x62],
    ];
    final argv = allocate((bytes.length + 1) * sizeOf<Pointer<Uint8>>())
        .cast<Pointer<Uint8>>();
    for (var i = 0; i < bytes.length; i++) {
      final value = allocate(bytes[i].length + 1).cast<Uint8>();
      value.asTypedList(bytes[i].length).setAll(0, bytes[i]);
      value[bytes[i].length] = 0;
      argv[i] = value;
    }
    argv[bytes.length] = nullptr;
    execv(argv[0], argv);
    throw StateError('execv returned without replacing the process');
  } finally {
    for (final address in storage) {
      free(address);
    }
  }
}
