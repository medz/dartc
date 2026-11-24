import 'dart:typed_data';

import 'package:dartc/emit.dart';

import 'bytes.dart';

/// Parts one after the other, each aligned to 16, with the offset of each.
typedef Packed = ({Uint8List bytes, Map<String, int> offsets});

Packed packParts(Map<String, Uint8List> parts) {
  final out = ByteWriter(.little), offsets = <String, int>{};
  for (final MapEntry(key: name, value: bytes) in parts.entries) {
    out.align(16);
    offsets[name] = out.length;
    out.bytes(bytes);
  }
  return (bytes: out.finish(), offsets: offsets);
}

/// The objects of [code] that are writable, or those that are not.
Packed packObjects(EmittedCode code, {required bool writable}) => packParts({
  for (final MapEntry(key: name, value: object) in code.objects.entries)
    if (object.writable == writable) name: object.bytes,
});
