import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_integers.dart' show MixedNative, MixedDart;

final class NativeIntegers() {
  final _library = NativeAssets(Target.host()).open('compiler/native_integers');
  final _storage = NativeAssets(Target.host()).open('compiler/integer_storage');
  late final memory = _storage.lookup<Uint8>('counter');
  late final accesses = [
    for (final name in [
      'Int8',
      'Uint8',
      'Int16',
      'Uint16',
      'Int32',
      'Uint32',
      'Int64',
      'Uint64',
    ])
      (
        read: _library.lookupFunction<Int64 Function(Int64), int Function(int)>(
          'read$name',
        ),
        write: _library
            .lookupFunction<
              Int64 Function(Int64, Int64),
              int Function(int, int)
            >('write$name'),
      ),
  ];
  late final conversions = [
    (
      extend: _library.lookupFunction<Int64 Function(Int8), int Function(int)>(
        'extendInt8',
      ),
      truncate: _library
          .lookupFunction<Int8 Function(Int64), int Function(int)>(
            'truncateInt8',
          ),
    ),
    (
      extend: _library.lookupFunction<Int64 Function(Uint8), int Function(int)>(
        'extendUint8',
      ),
      truncate: _library
          .lookupFunction<Uint8 Function(Int64), int Function(int)>(
            'truncateUint8',
          ),
    ),
    (
      extend: _library.lookupFunction<Int64 Function(Int16), int Function(int)>(
        'extendInt16',
      ),
      truncate: _library
          .lookupFunction<Int16 Function(Int64), int Function(int)>(
            'truncateInt16',
          ),
    ),
    (
      extend: _library
          .lookupFunction<Int64 Function(Uint16), int Function(int)>(
            'extendUint16',
          ),
      truncate: _library
          .lookupFunction<Uint16 Function(Int64), int Function(int)>(
            'truncateUint16',
          ),
    ),
    (
      extend: _library.lookupFunction<Int64 Function(Int32), int Function(int)>(
        'extendInt32',
      ),
      truncate: _library
          .lookupFunction<Int32 Function(Int64), int Function(int)>(
            'truncateInt32',
          ),
    ),
    (
      extend: _library
          .lookupFunction<Int64 Function(Uint32), int Function(int)>(
            'extendUint32',
          ),
      truncate: _library
          .lookupFunction<Uint32 Function(Int64), int Function(int)>(
            'truncateUint32',
          ),
    ),
  ];
  late final internal = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('internal');
  late final unsigned64 = _library
      .lookupFunction<Uint64 Function(Uint64), int Function(int)>('unsigned64');
  late final fromAddress = _library
      .lookupFunction<
        Pointer<Uint16> Function(Int64),
        Pointer<Uint16> Function(int)
      >('fromAddress');
  late final update = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint16>, Pointer<Int8>, Int64),
        int Function(Pointer<Uint16>, Pointer<Int8>, int)
      >('update');
  late final mixed = _library.lookupFunction<MixedNative, MixedDart>('mixed');

  void close() {
    _library.close();
    _storage.close();
  }
}
