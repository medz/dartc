import 'dart:convert';
import 'dart:typed_data';

Uint8List archiveBytes(List<(String, List<int>)> members) {
  final bytes = BytesBuilder()..add(ascii.encode('!<arch>\n'));
  for (final (name, contents) in members) {
    bytes
      ..add(
        ascii.encode(
          '${name.padRight(16)}${'0'.padRight(12)}${'0'.padRight(6)}'
          '${'0'.padRight(6)}${'100644'.padRight(8)}'
          '${'${contents.length}'.padRight(10)}`\n',
        ),
      )
      ..add(contents);
    if (contents.length.isOdd) bytes.addByte(10);
  }
  return bytes.takeBytes();
}
