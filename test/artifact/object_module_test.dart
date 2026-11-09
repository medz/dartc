import 'package:dartc/artifact.dart' as artifact;
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const target = Target(.linux, .arm64);
  test('owns bytes and symbols and rejects invalid ranges', () {
    final bytes = [0xc0, 0x03, 0x5f, 0xd6];
    final symbols = [const artifact.Symbol('return', 0, 4)];
    final object = artifact.ObjectModule(target, bytes, symbols);
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
        () => artifact.ObjectModule(target, object.code, invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => artifact.ObjectModule(target, [256, 0, 0, 0], []),
      throwsArgumentError,
    );
    expect(() => artifact.ObjectModule(target, [0], []), throwsArgumentError);
  });
  test(
    'validates symbol scope and relocation fields without losing imports',
    () {
      final code = [0, 0, 0, 0x94];
      const symbol = artifact.Symbol('entry', 0, 4);
      final imports = ['callee'];
      final refs = [const artifact.Relocation(0, .arm64Call26, 1)];
      final module = artifact.ObjectModule(
        target,
        code,
        [symbol],
        imports: imports,
        relocations: refs,
      );
      imports.clear();
      refs.clear();
      expect(module.imports, ['callee']);
      expect(module.relocations.single.symbol, 1);
      for (final ref in [
        const artifact.Relocation(-1, .arm64Call26, 0),
        const artifact.Relocation(1, .arm64Call26, 0),
        const artifact.Relocation(0, .x64Call32, 0),
        const artifact.Relocation(0, .arm64Call26, -1),
        const artifact.Relocation(0, .arm64Call26, 1),
        const artifact.Relocation(0, .arm64Branch26, 0),
      ]) {
        expect(
          () =>
              artifact.ObjectModule(target, code, [symbol], relocations: [ref]),
          throwsArgumentError,
        );
      }
      expect(
        () => artifact.ObjectModule(target, code, [symbol], imports: ['entry']),
        throwsArgumentError,
      );
      expect(
        () => artifact.ObjectModule(target, code, [
          const artifact.Symbol('local', 0, 4, binding: .local, exported: true),
        ]),
        throwsArgumentError,
      );
      expect(
        () => artifact.ObjectModule(
          target,
          [0xc0, 3, 0x5f, 0xd6],
          [symbol],
          relocations: [const artifact.Relocation(0, .arm64Call26, 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => artifact.ObjectModule(
          target,
          [1, 0, 0, 0x94],
          [symbol],
          relocations: [const artifact.Relocation(0, .arm64Call26, 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => artifact.ObjectModule(
          target,
          code,
          [symbol],
          relocations: [
            const artifact.Relocation(0, .arm64Call26, 0),
            const artifact.Relocation(0, .arm64Call26, 0),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
