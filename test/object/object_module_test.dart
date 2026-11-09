import 'package:dartc/object.dart' as native;
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const target = Target(.linux, .arm64);
  test('symbols preserve identity, aliases and missing extent', () {
    final symbols = [
      const native.Symbol('second', 0, 4, 4),
      const native.Symbol('label', 0, 4, null, kind: .unknown),
      const native.Symbol('first', 0, 0, 4),
      const native.Symbol('alias', 0, 0, 4),
    ];
    final module = native.ObjectModule(target, [
      native.Section.code(List.filled(8, 0)),
    ], symbols);
    expect(module.symbols, symbols);
    expect(module.symbols[1].size, isNull);
    expect(module.symbols[1].kind, native.SymbolKind.unknown);
  });
  test(
    'section identities validate storage and symbol/reference ownership',
    () {
      final bytes = [1, 2, 3],
          section = native.Section.data(bytes, alignment: 8);
      bytes.clear();
      expect(section.bytes, [1, 2, 3]);
      expect(section.size, 3);
      final zero = native.Section.zeroFill(0x100000000);
      expect(zero.bytes, isEmpty);
      expect(zero.size, 0x100000000);
      for (final alignment in [0, -1, 3]) {
        expect(
          () => native.Section.data([], alignment: alignment),
          throwsArgumentError,
        );
      }
      expect(() => native.Section.zeroFill(-1), throwsArgumentError);
      final sections = [
        native.Section.code([0, 0, 0, 0x94]),
        native.Section.data(List.filled(8, 0)),
      ];
      final valid = native.ObjectModule(target, sections, [
        const native.Symbol('f', 0, 0, 4),
        const native.Symbol('v', 1, 0, 8, kind: .data),
      ]);
      sections.clear();
      expect(valid.sections, hasLength(2));
      expect(() => valid.sections.clear(), throwsUnsupportedError);
      for (final symbol in [
        const native.Symbol('v', -1, 0, 8, kind: .data),
        const native.Symbol('v', 2, 0, 8, kind: .data),
        const native.Symbol('v', 1, 0, 9, kind: .data),
        const native.Symbol('f', 1, 0, 4),
      ]) {
        expect(
          () => native.ObjectModule(target, valid.sections, [symbol]),
          throwsArgumentError,
        );
      }
      for (final ref in [
        const native.Relocation.instruction(-1, 0, .arm64Call26, 0),
        const native.Relocation.instruction(2, 0, .arm64Call26, 0),
        const native.Relocation.instruction(1, 0, .arm64Call26, 0),
        const native.Relocation.instruction(0, 0, .arm64Call26, 1),
      ]) {
        expect(
          () => native.ObjectModule(
            target,
            valid.sections,
            valid.symbols,
            relocations: [ref],
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test('owns bytes and symbols and rejects invalid ranges', () {
    final bytes = [0xc0, 0x03, 0x5f, 0xd6];
    final symbols = [const native.Symbol('return', 0, 0, 4)];
    final object = native.ObjectModule(target, [
      native.Section.code(bytes),
    ], symbols);
    bytes.clear();
    symbols.clear();
    expect(object.sections.single.bytes, [0xc0, 0x03, 0x5f, 0xd6]);
    expect(object.symbols.single.name, 'return');
    expect(() => object.sections.single.bytes[0] = 0, throwsUnsupportedError);
    for (final invalid in [
      [const native.Symbol('a', 0, -1, 4)],
      [const native.Symbol('a', 0, 0, 5)],
      [const native.Symbol('a', 0, 0, 0)],
      [const native.Symbol('a', 0, 0, 4), const native.Symbol('a', 0, 0, 4)],
      [const native.Symbol('a\u0000b', 0, 0, 4)],
    ]) {
      expect(
        () => native.ObjectModule(target, object.sections, invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => native.ObjectModule(target, [
        native.Section.code([256, 0, 0, 0]),
      ], []),
      throwsArgumentError,
    );
    expect(
      () => native.ObjectModule(target, [
        native.Section.code([0]),
      ], []),
      throwsArgumentError,
    );
  });
  test(
    'validates symbol scope and relocation fields without losing imports',
    () {
      final code = [0, 0, 0, 0x94];
      const symbol = native.Symbol('entry', 0, 0, 4);
      final imports = ['callee'];
      final refs = [const native.Relocation.instruction(0, 0, .arm64Call26, 1)];
      final module = native.ObjectModule(
        target,
        [native.Section.code(code)],
        [symbol],
        imports: imports,
        relocations: refs,
      );
      imports.clear();
      refs.clear();
      expect(module.imports, ['callee']);
      expect(module.relocations.single.symbol, 1);
      for (final ref in [
        const native.Relocation.instruction(0, -1, .arm64Call26, 0),
        const native.Relocation.instruction(0, 1, .arm64Call26, 0),
        const native.Relocation.instruction(0, 0, .x64Call32, 0),
        const native.Relocation.instruction(0, 0, .arm64Call26, -1),
        const native.Relocation.instruction(0, 0, .arm64Call26, 1),
        const native.Relocation.instruction(0, 0, .arm64Branch26, 0),
        const native.Relocation.instruction(
          0,
          0,
          .arm64Call26,
          0,
          indirect: true,
        ),
      ]) {
        expect(
          () => native.ObjectModule(
            target,
            [native.Section.code(code)],
            [symbol],
            relocations: [ref],
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => native.ObjectModule(
          target,
          [native.Section.code(code)],
          [symbol],
          imports: ['entry'],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [native.Section.code(code)],
          [
            const native.Symbol(
              'local',
              0,
              0,
              4,
              binding: .local,
              exported: true,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [
            native.Section.code([0xc0, 3, 0x5f, 0xd6]),
          ],
          [symbol],
          relocations: [
            const native.Relocation.instruction(0, 0, .arm64Call26, 0),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [
            native.Section.code([1, 0, 0, 0x94]),
          ],
          [symbol],
          relocations: [
            const native.Relocation.instruction(0, 0, .arm64Call26, 0),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => native.ObjectModule(
          target,
          [native.Section.code(code)],
          [symbol],
          relocations: [
            const native.Relocation.instruction(0, 0, .arm64Call26, 0),
            const native.Relocation.instruction(0, 0, .arm64Call26, 0),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
