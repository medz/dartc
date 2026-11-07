import 'package:dartc/artifact.dart' as artifact;
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const target = Target(.linux, .arm64);
  test('owns bytes and symbols and rejects invalid ranges', () {
    final bytes = [0xc0, 0x03, 0x5f, 0xd6];
    final symbols = [const artifact.Symbol('return', 0, 4)];
    final object = artifact.ObjectFile(target, bytes, symbols);
    bytes.clear();
    symbols.clear();
    expect(object.code, [0xc0, 0x03, 0x5f, 0xd6]);
    expect(object.symbols.single.name, 'return');
    expect(() => object.code[0] = 0, throwsUnsupportedError);
    for (final invalid in [
      [const artifact.Symbol('a', -1, 4)],
      [const artifact.Symbol('a', 0, 5)],
      [const artifact.Symbol('a', 0, 0)],
      [const artifact.Symbol('a', 0, 4), const artifact.Symbol('b', 0, 4)],
      [const artifact.Symbol('a\u0000b', 0, 4)],
    ]) {
      expect(
        () => artifact.ObjectFile(target, object.code, invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => artifact.ObjectFile(target, [256, 0, 0, 0], []),
      throwsArgumentError,
    );
    expect(() => artifact.ObjectFile(target, [0], []), throwsArgumentError);
  });
}
