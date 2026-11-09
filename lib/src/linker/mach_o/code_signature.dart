import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A Mach-O ad-hoc signature covering all bytes before [codeLimit].
final class CodeSignature(
  String identifier,
  final int codeLimit,
  final int textSize, {
  final bool executable = false,
}) {
  final Uint8List _identifier = utf8.encode(identifier);

  int get _slots => (codeLimit + 4095) ~/ 4096;
  int get _hashOffset => 88 + _identifier.length + 1;

  /// The signature size including its enclosing superblob and alignment.
  int get size => (20 + _hashOffset + _slots * 32 + 15) & ~15;

  /// Writes the signature after the finalized load commands and code in [image].
  void write(Uint8List image) {
    final data = ByteData.sublistView(image, codeLimit, codeLimit + size);
    data.setUint32(0, 0xfade0cc0);
    data.setUint32(4, size);
    data.setUint32(8, 1);
    data.setUint32(16, 20);
    const directory = 20;
    data.setUint32(directory, 0xfade0c02);
    data.setUint32(directory + 4, _hashOffset + _slots * 32);
    data.setUint32(directory + 8, 0x20400);
    data.setUint32(directory + 12, 0x20002); // CS_ADHOC | CS_LINKER_SIGNED.
    data.setUint32(directory + 16, _hashOffset);
    data.setUint32(directory + 20, 88);
    data.setUint32(directory + 28, _slots);
    data.setUint32(directory + 32, codeLimit);
    data.setUint8(directory + 36, 32);
    data.setUint8(directory + 37, 2); // SHA-256.
    data.setUint8(directory + 39, 12);
    data.setUint64(directory + 72, textSize);
    data.setUint64(directory + 80, executable ? 1 : 0);
    image.setAll(codeLimit + directory + 88, _identifier);
    for (var slot = 0; slot < _slots; slot++) {
      final start = slot * 4096;
      final end = start + 4096 < codeLimit ? start + 4096 : codeLimit;
      final hash = sha256.convert(Uint8List.sublistView(image, start, end));
      image.setAll(codeLimit + directory + _hashOffset + slot * 32, hash.bytes);
    }
  }
}
