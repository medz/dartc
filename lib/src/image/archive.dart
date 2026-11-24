import 'dart:typed_data';

import 'bytes.dart';

const _magic = '!<arch>\n', _headerBytes = 60;
const _indexName = '__.SYMDEF SORTED';

/// A library of one [object] file called [name] that has [symbols].
Uint8List writeArchive(
  Uint8List object,
  String name,
  Iterable<String> symbols,
) {
  final sorted = [for (final symbol in symbols) '_$symbol']..sort();
  final texts = ByteWriter(.little), offsets = <int>[];
  for (final symbol in sorted) {
    offsets.add(texts.length);
    texts
      ..bytes(symbol.codeUnits)
      ..u8(0);
  }
  texts.align(8);
  final indexBytes = 4 + sorted.length * 8 + 4 + texts.length;
  final objectAt = _magic.length + _memberBytes(_indexName, indexBytes);
  final index = ByteWriter(.little)..u32(sorted.length * 8);
  for (final offset in offsets) {
    index
      ..u32(offset)
      ..u32(objectAt);
  }
  index
    ..u32(texts.length)
    ..bytes(texts.finish());
  final out = ByteWriter(.little)..bytes(_magic.codeUnits);
  _writeMember(out, _indexName, index.finish());
  _writeMember(out, name, object);
  return out.finish();
}

/// Names come before contents, at lengths that keep those aligned to 8.
int _nameBytes(String name) => (name.length + 4) ~/ 8 * 8 + 4;

int _memberBytes(String name, int contents) =>
    _headerBytes + _nameBytes(name) + (contents + 7) ~/ 8 * 8;

void _writeMember(ByteWriter out, String name, Uint8List contents) {
  final nameBytes = _nameBytes(name);
  final size = nameBytes + (contents.length + 7) ~/ 8 * 8;
  void field(String text, int width) => out.text(text.padRight(width), width);
  field('#1/$nameBytes', 16);
  field('0', 12);
  field('0', 6);
  field('0', 6);
  field('100644', 8);
  field('$size', 10);
  out
    ..text('`\n', 2)
    ..text(name, nameBytes)
    ..bytes(contents)
    ..zeros(-contents.length % 8);
}
