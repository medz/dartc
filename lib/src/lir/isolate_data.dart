import 'dart:typed_data';

import 'module.dart';

/// The data that each isolate has a copy of, as one object: its bytes, the
/// objects that it refers to by where they are in it, and where each symbol is
/// in it.
typedef IsolateData = ({
  Uint8List bytes,
  Map<int, String> references,
  Map<String, int> offsets,
});

/// Lays out what of [data] and [statics] is isolated, each part 16-aligned.
IsolateData isolateData(Iterable<LirData> data, Iterable<LirStatic> statics) {
  final offsets = <String, int>{}, references = <int, String>{};
  final bytes = BytesBuilder();
  void add(String name, Uint8List part, Map<int, String> referring) {
    while (bytes.length % 16 != 0) {
      bytes.addByte(0);
    }
    offsets[name] = bytes.length;
    referring.forEach((at, target) => references[bytes.length + at] = target);
    bytes.add(part);
  }

  for (final part in data) {
    if (part.isolated) add(part.name, part.bytes, const {});
  }
  for (final object in statics) {
    if (object.isolated) add(object.name, object.bytes, object.references);
  }
  return (bytes: bytes.takeBytes(), references: references, offsets: offsets);
}
