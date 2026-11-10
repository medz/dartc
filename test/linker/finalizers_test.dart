import 'dart:typed_data';

import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/linker/mach_o/finalizers.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      final Linker linker = os == .macos
          ? MachOLinker(target)
          : ElfLinker(target);
      final code = arch == .arm64 ? [0xc0, 3, 0x5f, 0xd6] : [0xc3];
      ObjectModule owner(String name) => ObjectModule(
        target,
        [Section.code(code), Section.finalizers(Uint8List(8))],
        [
          Symbol(name, 0, 0, code.length, exported: true),
          Symbol('cleanup', 0, 0, code.length, binding: .local),
        ],
        relocations: [const Relocation.address(1, 0, 1)],
      );
      final first = owner('first'), second = owner('second');
      if (os == .macos) {
        test('$target tests only the C int registration result', () {
          final transformed = registerFinalizers(first);
          final register =
              transformed.symbols.length +
              transformed.imports.indexOf(finalizerServices.keys.first);
          final call = transformed.relocations
              .whereType<InstructionRelocation>()
              .singleWhere((r) => r.symbol == register);
          final bytes = transformed.sections[call.section].bytes;
          final afterCall = call.offset + 4;
          // UBFM x0,x0,#0,#31 / MOV eax,eax discards unspecified upper bits.
          final normalize = arch == .arm64
              ? [0x00, 0x7c, 0x40, 0xd3]
              : [0x40, 0x8b, 0xc0];
          expect(
            bytes.sublist(afterCall, afterCall + normalize.length),
            normalize,
          );
        });
        test('$target registers array order, not relocation-list order', () {
          final original = ObjectModule(
            target,
            [
              Section.code([...code, ...code]),
              Section.finalizers(Uint8List(16)),
            ],
            [
              Symbol('first', 0, 0, code.length, binding: .local),
              Symbol('second', 0, code.length, code.length, binding: .local),
            ],
            relocations: [
              const Relocation.address(1, 8, 1),
              const Relocation.address(1, 0, 0),
            ],
          );
          final transformed = registerFinalizers(original);
          final pointers = transformed.relocations
              .whereType<AddressRelocation>()
              .toList();
          expect(pointers.map((r) => (r.offset, r.symbol)), [(0, 2), (8, 3)]);
          final targets = transformed.relocations
              .whereType<InstructionRelocation>()
              .where((r) => r.symbol < 2)
              .map((r) => r.symbol)
              .toList();
          expect(targets, arch == .arm64 ? [0, 0, 1, 1] : [0, 1]);
        });
        test(
          '$target registration preserves prior symbol and import indices',
          () {
            final original = ObjectModule(
              target,
              [...first.sections, Section.data(Uint8List(8), alignment: 8)],
              first.symbols,
              imports: ['external'],
              relocations: [
                ...first.relocations,
                Relocation.address(2, 0, first.symbols.length),
              ],
            );
            final transformed = registerFinalizers(original);
            expect(
              transformed.symbols.take(original.symbols.length),
              original.symbols,
            );
            expect(
              transformed.sections.take(original.sections.length),
              original.sections,
            );
            final address = transformed.relocations.singleWhere(
              (r) => r.section == 2,
            );
            expect(
              transformed.imports[address.symbol - transformed.symbols.length],
              'external',
            );
            expect(transformed.imports.skip(1), finalizerServices.keys);
          },
        );
      }

      test(
        '$target aggregates finalizer-only writable storage with loader metadata',
        () {
          final image = linker.linkSharedLibrary([
            .object(format.decodeObject(format.encodeObject(first))),
            .object(second),
          ], name: 'finalizers');
          final data = ByteData.sublistView(image);
          late int offset, address, size;
          if (os == .linux) {
            final headers = data.getUint64(40, .little);
            final header = headers + 128;
            expect(data.getUint32(header + 4, .little), 15);
            expect(data.getUint64(header + 8, .little), 3);
            expect(data.getUint64(header + 56, .little), 8);
            offset = data.getUint64(header + 24, .little);
            address = data.getUint64(header + 16, .little);
            size = data.getUint64(header + 32, .little);
            final tags = <int, int>{};
            for (var i = 0; i < data.getUint16(56, .little); i++) {
              final ph = 64 + i * 56;
              if (data.getUint32(ph, .little) != 2) continue;
              final at = data.getUint64(ph + 8, .little),
                  length = data.getUint64(ph + 32, .little);
              for (var j = at; j < at + length; j += 16) {
                tags[data.getUint64(j, .little)] = data.getUint64(
                  j + 8,
                  .little,
                );
              }
            }
            expect(tags[26], address);
            expect(tags[28], size);
            expect(tags[8], 48); // One relative relocation per owner.
          } else {
            var cursor = 32;
            var found = false;
            for (var i = 0; i < data.getUint32(16, .little); i++) {
              if (data.getUint32(cursor, .little) == 0x19) {
                for (var j = 0; j < data.getUint32(cursor + 64, .little); j++) {
                  final header = cursor + 72 + j * 80;
                  expect(data.getUint32(header + 64, .little), isNot(0xa));
                  if (data.getUint32(header + 64, .little) != 0x9) continue;
                  expect(data.getUint32(cursor + 60, .little), 3);
                  offset = data.getUint32(header + 48, .little);
                  address = data.getUint64(header + 32, .little);
                  size = data.getUint64(header + 40, .little);
                  found = true;
                }
              }
              cursor += data.getUint32(cursor + 4, .little);
            }
            expect(found, isTrue);
          }
          expect(size, 16);
          expect(address % 8, 0);
          final pointers = [
            data.getUint64(offset, .little),
            data.getUint64(offset + 8, .little),
          ];
          if (os == .linux) expect(pointers[1] - pointers[0], 16);
          for (final pointer in os == .linux ? pointers : <int>[]) {
            expect(image.sublist(pointer, pointer + code.length), code);
          }
        },
      );
      test(
        '$target rejects finalizers from executable objects and selected archives',
        () {
          final archive = Archive.decode(ArchiveWriter(format).encode([first]));
          for (final input in [
            LinkInput.object(first),
            LinkInput.archive(archive),
          ]) {
            expect(
              () => linker.linkExecutable([input], entry: 'first'),
              throwsUnsupportedError,
            );
          }
        },
      );
    }
  }
}
