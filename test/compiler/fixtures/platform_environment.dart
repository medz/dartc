import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:dartc/interop.dart';

class Cell(final int value);

int churn(int count) {
  var sum = 0;
  for (var i = 0; i < count; i++) {
    sum += Cell(i).value;
  }
  return sum;
}

@Export<ffi.Int64 Function(ffi.Int64)>()
int environmentLength(int count) {
  final value = Platform.environment['DARTC_VALUE'] ?? '';
  churn(count);
  return value.length;
}

void main() {
  final environment = Platform.environment;
  final original = environment['DARTC_VALUE'];
  print(
    '${Platform.operatingSystem}:${Platform.pathSeparator}:'
    '${Platform.isLinux}:${Platform.isMacOS}:${Platform.isWindows}',
  );
  print(
    jsonEncode([
      for (final key in [
        'DARTC_VALUE',
        'DARTC_EMPTY',
        'DARTC_EQUALS',
        'DARTC_UNICODE',
        '\ufeffDARTC_BOM',
        'DARTC_BAD',
        'DARTC_DUP',
      ])
        environment[key],
      environment.containsKey(''),
      environment.containsKey('DARTC_NO_EQUALS'),
    ]),
  );
  final process = ffi.DynamicLibrary.process();
  final malloc = process
      .lookupFunction<
        ffi.Pointer<ffi.Uint8> Function(ffi.Size),
        ffi.Pointer<ffi.Uint8> Function(int)
      >('malloc');
  final free = process
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Uint8>),
        void Function(ffi.Pointer<ffi.Uint8>)
      >('free');
  final setenv = process
      .lookupFunction<
        ffi.Int Function(
          ffi.Pointer<ffi.Uint8>,
          ffi.Pointer<ffi.Uint8>,
          ffi.Int,
        ),
        int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, int)
      >('setenv');
  const name = 'DARTC_VALUE';
  final bytes = utf8.encode('$name\u0000changed\u0000');
  final storage = malloc(bytes.length);
  if (storage == ffi.nullptr) throw StateError('malloc failed');
  try {
    storage.asTypedList(bytes.length).setAll(0, bytes);
    if (setenv(storage, storage + name.length + 1, 1) != 0) {
      throw StateError('setenv failed');
    }
  } finally {
    free(storage);
  }
  var rejected = 0;
  for (final change in <void Function()>[
    () => environment['DARTC_VALUE'] = 'mutated',
    () => environment.remove('DARTC_VALUE'),
    () => environment.clear(),
  ]) {
    try {
      change();
    } on UnsupportedError {
      rejected++;
    }
  }
  final sum = churn(40000);
  print(
    '${identical(environment, Platform.environment)}:'
    '${Platform.environment['DARTC_VALUE'] == original}:$rejected:$sum',
  );
}
