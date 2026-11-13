import 'dart:convert';
import 'dart:ffi';

void main(List<String> arguments) {
  if (arguments.length < 2 ||
      !const ['arguments', 'environment'].contains(arguments.first)) {
    throw ArgumentError('Expected a raw input mode and executable.');
  }
  final mode = arguments.first;
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
  final execve = process
      .lookupFunction<
        Int32 Function(
          Pointer<Uint8>,
          Pointer<Pointer<Uint8>>,
          Pointer<Pointer<Uint8>>,
        ),
        int Function(
          Pointer<Uint8>,
          Pointer<Pointer<Uint8>>,
          Pointer<Pointer<Uint8>>,
        )
      >('execve');
  final storage = <Pointer<Void>>[];
  Pointer<Void> allocate(int bytes) {
    final address = malloc(bytes);
    if (address.address == 0) throw StateError('malloc failed');
    storage.add(address);
    return address;
  }

  Pointer<Pointer<Uint8>> vector(List<List<int>> bytes) {
    final array = allocate((bytes.length + 1) * sizeOf<Pointer<Uint8>>())
        .cast<Pointer<Uint8>>();
    for (var i = 0; i < bytes.length; i++) {
      final value = allocate(bytes[i].length + 1).cast<Uint8>();
      value.asTypedList(bytes[i].length).setAll(0, bytes[i]);
      value[bytes[i].length] = 0;
      array[i] = value;
    }
    array[bytes.length] = nullptr;
    return array;
  }

  try {
    final argv = vector([
      for (final argument in arguments.skip(1)) utf8.encode(argument),
      if (mode == 'arguments') [0x61, 0xff, 0x62],
    ]);
    final envp = mode == 'environment'
        ? vector([
            for (final entry in [
              'DARTC_VALUE=raw',
              'DARTC_EMPTY=',
              'DARTC_EQUALS=a=b=c',
              'DARTC_UNICODE=中文🙂',
              '\ufeffDARTC_BOM=kept',
              'DARTC_DUP=first',
              'DARTC_DUP=last',
              'DARTC_NO_EQUALS',
              '=invalid',
              '',
            ])
              utf8.encode(entry),
            [...utf8.encode('DARTC_BAD='), 0xff],
          ])
        : process.lookup<Pointer<Pointer<Uint8>>>('environ').value;
    execve(argv[0], argv, envp);
    throw StateError('execve returned without replacing the process');
  } finally {
    for (final address in storage) {
      free(address);
    }
  }
}
