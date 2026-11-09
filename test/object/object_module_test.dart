import 'package:dartc/object.dart' as native;
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const target = Target(.linux, .arm64);
  test('owns bytes and symbols and rejects invalid ranges', () {
    final bytes = [0xc0, 0x03, 0x5f, 0xd6];
    final symbols = [const native.Symbol('return', 0, 4)];
    final object = native.ObjectModule(target, bytes, symbols);
    bytes.clear();
    symbols.clear();
    expect(object.code, [0xc0, 0x03, 0x5f, 0xd6]);
    expect(object.symbols.single.name, 'return');
    expect(() => object.code[0] = 0, throwsUnsupportedError);
    for (final invalid in [
      [const native.Symbol('a', -1, 4)],
      [const native.Symbol('a', 0, 5)],
      [const native.Symbol('a', 0, 0)],
      [const native.Symbol('a', 0, 4), const native.Symbol('b', 0, 4)],
      [const native.Symbol('a\u0000b', 0, 4)],
    ]) {
      expect(
        () => native.ObjectModule(target, object.code, invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => native.ObjectModule(target, [256, 0, 0, 0], []),
      throwsArgumentError,
    );
    expect(() => native.ObjectModule(target, [0], []), throwsArgumentError);
  });
  test(
    'validates symbol scope and relocation fields without losing imports',
    () {
      final code = [0, 0, 0, 0x94];
      const symbol = native.Symbol('entry', 0, 4);
      final imports = ['callee'];
      final refs = [const native.Relocation(0, .arm64Call26, 1)];
      final module = native.ObjectModule(
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
        const native.Relocation(-1, .arm64Call26, 0),
        const native.Relocation(1, .arm64Call26, 0),
        const native.Relocation(0, .x64Call32, 0),
        const native.Relocation(0, .arm64Call26, -1),
        const native.Relocation(0, .arm64Call26, 1),
        const native.Relocation(0, .arm64Branch26, 0),
      ]) {
        expect(
          () => native.ObjectModule(target, code, [symbol], relocations: [ref]),
          throwsArgumentError,
        );
      }
      expect(
        () => native.ObjectModule(target, code, [symbol], imports: ['entry']),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(target, code, [
          const native.Symbol('local', 0, 4, binding: .local, exported: true),
        ]),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [0xc0, 3, 0x5f, 0xd6],
          [symbol],
          relocations: [const native.Relocation(0, .arm64Call26, 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [1, 0, 0, 0x94],
          [symbol],
          relocations: [const native.Relocation(0, .arm64Call26, 0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          code,
          [symbol],
          relocations: [
            const native.Relocation(0, .arm64Call26, 0),
            const native.Relocation(0, .arm64Call26, 0),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
