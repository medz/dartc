import 'dart:typed_data';

import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch), assets = NativeAssets(target);
      final darwin = os == .macos;
      final ObjectFormat format = darwin ? MachO(target) : Elf(target);
      final Linker linker = darwin ? MachOLinker(target) : ElfLinker(target);
      test(
        '$target reads fixed objects and relinks the same native images',
        () {
          for (final fixture in [
            'arithmetic',
            'calls',
            'control_flow',
            'stack_calls',
            'integer_operations',
            'pointers',
          ]) {
            final bytes = assets.file('compiler/$fixture.o').readAsBytesSync();
            final module = format.decodeObject(bytes);
            expect(format.encodeObject(module), bytes, reason: fixture);
            final library = assets.library('compiler/$fixture');
            expect(
              linker.linkSharedLibrary([
                .object(module),
              ], name: library.uri.pathSegments.last),
              library.readAsBytesSync(),
              reason: fixture,
            );
          }
          for (final (name, files) in [
            ('values', ['0', '1']),
            ('calls', ['call_0', 'call_1']),
            ('data', ['data_0', 'data_1']),
            ('storage', ['data_0']),
          ]) {
            final modules = <ObjectModule>[];
            for (final file in files) {
              final bytes = assets.file('linker/$file.o').readAsBytesSync();
              final module = format.decodeObject(bytes);
              expect(format.encodeObject(module), bytes, reason: file);
              if (darwin) {
                expect(module.symbols.map((s) => s.size), everyElement(isNull));
                expect(
                  module.symbols.map((s) => s.kind),
                  everyElement(SymbolKind.unknown),
                );
              }
              modules.add(module);
            }
            final library = assets.library('linker/$name');
            expect(
              linker.linkSharedLibrary(
                modules.map(LinkInput.object),
                name: library.uri.pathSegments.last,
              ),
              library.readAsBytesSync(),
              reason: name,
            );
          }
          final empty = ObjectModule(target, [], []);
          expect(
            format.encodeObject(
              format.decodeObject(format.encodeObject(empty)),
            ),
            format.encodeObject(empty),
          );
          final original = format.decodeObject(
            assets.file('compiler/arithmetic.o').readAsBytesSync(),
          );
          final entry = original.symbols.first;
          final aliased = ObjectModule(
            target,
            original.sections,
            [
              ...original.symbols,
              Symbol(
                'alias',
                entry.section,
                entry.offset,
                entry.size,
                kind: entry.kind,
                exported: true,
              ),
            ],
            imports: original.imports,
            relocations: original.relocations,
          );
          final decoded = format.decodeObject(format.encodeObject(aliased));
          expect(decoded.symbols.last.name, 'alias');
          expect(
            linker.linkSharedLibrary([.object(decoded)], name: 'aliases'),
            linker.linkSharedLibrary([.object(aliased)], name: 'aliases'),
          );
        },
      );

      test('$target owns decoded contents and accepts offset byte views', () {
        final original = assets.file('linker/data_0.o').readAsBytesSync();
        final buffer = Uint8List(original.length + 16)..setAll(8, original);
        final module = format.decodeObject(
          Uint8List.sublistView(buffer, 8, buffer.length - 8),
        );
        buffer.fillRange(0, buffer.length, 0xff);
        expect(format.encodeObject(module), original);
        expect(
          () => module.sections.first.bytes[0] = 1,
          throwsUnsupportedError,
        );
        expect(module.sections.last.kind, SectionKind.zeroFill);
        expect(module.sections.last.bytes, isEmpty);
        expect(module.sections.last.size, 0x20020);
        final counter = module.symbols.singleWhere(
          (s) => s.name.endsWith('counter'),
        );
        expect(counter.offset, 0x10008);
        expect(counter.exported, isTrue);
      });

      test(
        '$target rejects corrupt records and unsupported object features',
        () {
          final original = assets.file('linker/data_1.o').readAsBytesSync();
          for (final length in [0, 3, 31, 63, original.length - 1]) {
            expect(
              () => format.decodeObject(
                Uint8List.sublistView(original, 0, length),
              ),
              throwsFormatException,
            );
          }
          final data = ByteData.sublistView(original);
          final int section, symbols, strings, relocation, firstSymbol;
          int? symtab, headers;
          if (darwin) {
            section = 104;
            symtab = 32 + data.getUint32(36, .little) + 24;
            symbols = data.getUint32(symtab + 8, .little);
            strings = data.getUint32(symtab + 16, .little);
            relocation = data.getUint32(section + 56, .little);
            firstSymbol = symbols;
          } else {
            headers = data.getUint64(40, .little);
            section = headers + 64;
            symtab = headers + 3 * 64;
            symbols = data.getUint64(symtab + 24, .little);
            strings = data.getUint64(headers + 4 * 64 + 24, .little);
            relocation = data.getUint64(headers + 7 * 64 + 24, .little);
            firstSymbol = symbols + 24;
          }
          final code = darwin
              ? data.getUint32(section + 48, .little)
              : data.getUint64(section + 24, .little);
          final corruptions = <String, void Function(ByteData)>{
            'magic': (d) => d.setUint8(0, 0),
            'symbol name': (d) => d.setUint32(firstSymbol, 0xffffffff, .little),
            'symbol address': (d) =>
                d.setUint64(firstSymbol + 8, 0x7fffffffffffffff, .little),
            'string sentinel': (d) => d.setUint8(strings, 1),
            'symbol section': (d) => darwin
                ? d.setUint8(firstSymbol + 5, 200)
                : d.setUint16(firstSymbol + 6, 200, .little),
            'relocation site': (d) => darwin
                ? d.setUint32(relocation, 0x7fffffff, .little)
                : d.setUint64(relocation, 0x7fffffff, .little),
            'relocation symbol': (d) => darwin
                ? d.setUint32(
                    relocation + 4,
                    (data.getUint32(relocation + 4, .little) & 0xff000000) |
                        0xffffff,
                    .little,
                  )
                : d.setUint64(
                    relocation + 8,
                    (0xffffffff << 32) |
                        (data.getUint64(relocation + 8, .little) & 0xffffffff),
                    .little,
                  ),
            'symbol table size': (d) => darwin
                ? d.setUint32(symtab! + 12, 0xffffffff, .little)
                : d.setUint64(symtab! + 32, 0x7fffffffffffffff, .little),
            'section file overlap': (d) => darwin
                ? d.setUint32(section + 48, 0, .little)
                : d.setUint64(section + 24, 0, .little),
            'section alignment': (d) => darwin
                ? d.setUint32(section + 52, 20, .little)
                : d.setUint64(section + 48, 3, .little),
            if (darwin) 'command size': (d) => d.setUint32(36, 4, .little),
            if (!darwin)
              'section table overlap': (d) => d.setUint64(40, 0, .little),
          };
          for (final MapEntry(key: name, value: corrupt)
              in corruptions.entries) {
            final bytes = Uint8List.fromList(original);
            corrupt(ByteData.sublistView(bytes));
            expect(
              () => format.decodeObject(bytes),
              throwsFormatException,
              reason: name,
            );
          }
          final unsupported = <String, void Function(ByteData)>{
            'instruction form': (d) => d.setUint32(code, 0, .little),
            'implicit addend': (d) => arch == .arm64
                ? d.setUint32(
                    code,
                    data.getUint32(code, .little) | 0x20000000,
                    .little,
                  )
                : d.setUint32(code + 3, 1, .little),
            'target': (d) => darwin
                ? d.setUint32(4, 0, .little)
                : d.setUint16(18, 0, .little),
            'section attributes': (d) => darwin
                ? d.setUint32(section + 64, 2, .little)
                : d.setUint64(section + 8, 0x400, .little),
            'symbol kind': (d) =>
                d.setUint8(firstSymbol + 4, darwin ? 0x2 : 0x20),
            'relocation type': (d) => darwin
                ? d.setUint32(
                    relocation + 4,
                    (data.getUint32(relocation + 4, .little) & 0xffffff) |
                        0x6d000000,
                    .little,
                  )
                : d.setUint64(
                    relocation + 8,
                    (data.getUint64(relocation + 8, .little) & ~0xffffffff) | 1,
                    .little,
                  ),
            if (!darwin)
              'symbol addend': (d) => d.setInt64(relocation + 16, 1, .little),
          };
          for (final MapEntry(key: name, value: alter) in unsupported.entries) {
            final bytes = Uint8List.fromList(original);
            alter(ByteData.sublistView(bytes));
            expect(
              () => format.decodeObject(bytes),
              throwsUnsupportedError,
              reason: name,
            );
          }
        },
      );
    }
  }
}
