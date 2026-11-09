@Tags(['assets'])
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final (arch, name) in [
    for (final arch in Architecture.values)
      for (final name in [
        'symbols',
        'shared_calls',
        'addresses_shared',
        'addresses_static',
      ])
        (arch, name),
  ]) {
    final target = Target(.macos, arch),
        assets = NativeAssets(Target(.macos, arch));
    test('$target $name signature covers every image page', () {
      final bytes = assets.library('linker/$name').readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      var command = 32, signature = -1;
      for (var i = 0; i < data.getUint32(16, .little); i++) {
        if (data.getUint32(command, .little) == 0x1d) {
          signature = data.getUint32(command + 8, .little);
          expect(
            signature + data.getUint32(command + 12, .little),
            bytes.length,
          );
        }
        command += data.getUint32(command + 4, .little);
      }
      expect(signature, isNonNegative);
      expect(data.getUint32(signature), 0xfade0cc0);
      expect(data.getUint32(signature + 8), 1);
      final directory = signature + data.getUint32(signature + 16);
      expect(data.getUint32(directory), 0xfade0c02);
      expect(data.getUint32(directory + 32), signature);
      expect(data.getUint8(directory + 36), 32);
      expect(data.getUint8(directory + 37), 2);
      final pageSize = 1 << data.getUint8(directory + 39);
      final slots = data.getUint32(directory + 28);
      expect(slots, (signature + pageSize - 1) ~/ pageSize);
      final hashes = directory + data.getUint32(directory + 16);
      for (var slot = 0; slot < slots; slot++) {
        final start = slot * pageSize;
        final end = start + pageSize < signature ? start + pageSize : signature;
        expect(
          bytes.sublist(hashes + slot * 32, hashes + (slot + 1) * 32),
          sha256.convert(Uint8List.sublistView(bytes, start, end)).bytes,
        );
      }
    });
  }
}
