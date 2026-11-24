import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

const _magic = '!<arch>\n', _headerBytes = 60, _longestName = 15;

/// A library of one ELF [object] file called [name] that has [symbols].
Uint8List writeElfArchive(
  Uint8List object,
  String name,
  Iterable<String> symbols,
) {
  final bytes = utf8.encode(name);
  final isLong = bytes.length > _longestName;
  final names = ByteWriter(.little);
  if (isLong) {
    names
      ..bytes(bytes)
      ..bytes('/\n'.codeUnits);
  }
  final texts = ByteWriter(.little);
  for (final symbol in symbols) {
    texts
      ..bytes(utf8.encode(symbol))
      ..u8(0);
  }
  final indexBytes = 4 + symbols.length * 4 + texts.length;
  var objectAt = _magic.length + _memberBytes(indexBytes);
  if (isLong) objectAt += _memberBytes(names.length);
  final index = ByteWriter(.big)..u32(symbols.length);
  for (var i = 0; i < symbols.length; i++) {
    index.u32(objectAt);
  }
  index.bytes(texts.finish());
  final out = ByteWriter(.little)..bytes(_magic.codeUnits);
  _writeMember(out, '/', index.finish());
  if (isLong) _writeMember(out, '//', names.finish());
  _writeMember(out, isLong ? '/0' : '$name/', object);
  return out.finish();
}

int _memberBytes(int contents) => _headerBytes + contents + contents % 2;

void _writeMember(ByteWriter out, String name, Uint8List contents) {
  void field(String text, int width) => out.text(text.padRight(width), width);
  field(name, 16);
  field('0', 12);
  field('0', 6);
  field('0', 6);
  field('100644', 8);
  field('${contents.length}', 10);
  out
    ..text('`\n', 2)
    ..bytes(contents)
    ..zeros(contents.length % 2);
}
