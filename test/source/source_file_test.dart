import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  test('SourceFile preserves source text and shares its line index', () {
    final uri = Uri.parse('memory:example.dart');
    final source = SourceFile(uri, '\uFEFFa\r\n\uD800');
    expect(source.uri, uri);
    expect(source.text.codeUnits, [0xFEFF, 0x61, 0x0D, 0x0A, 0xD800]);
    expect(source.lineInfo, same(source.lineInfo));
    expect(source.lineInfo.location(source.length), (line: 2, column: 2));
  });
}
