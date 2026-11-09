import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      final module = ObjectModule(
        target,
        [
          Section.readOnlyData(Uint8List(16), alignment: 8),
          Section.data(Uint8List(16), alignment: 8),
        ],
        [
          const Symbol('local', 1, 8, 8, kind: .data, binding: .local),
          const Symbol('table', 0, 0, 16, kind: .data, exported: true),
        ],
        imports: ['external'],
        relocations: [
          const .address(0, 0, 0),
          const .address(0, 8, 2),
          const .address(1, 0, 1),
        ],
      );
      test('$target preserves absolute data references in object files', () {
        final bytes = format.encodeObject(module);
        final decoded = format.decodeObject(bytes);
        expect(decoded.relocations, everyElement(isA<AddressRelocation>()));
        expect(
          decoded.relocations.map((r) => (r.section, r.offset, r.symbol)),
          unorderedEquals([(0, 0, 0), (0, 8, 2), (1, 0, 1)]),
        );
        expect(decoded.imports, ['external']);
        expect(format.encodeObject(decoded), bytes);

        final data = ByteData.sublistView(bytes);
        final int relocation, contents;
        if (os == .macos) {
          relocation = data.getUint32(160, .little);
          contents = data.getUint32(152, .little);
          expect(data.getUint32(relocation + 4, .little) >> 24, 0x0e);
        } else {
          final headers = data.getUint64(40, .little);
          contents = data.getUint64(headers + 64 + 24, .little);
          final index = Iterable<int>.generate(data.getUint16(60, .little))
              .firstWhere(
                (i) => data.getUint32(headers + i * 64 + 4, .little) == 4,
              );
          relocation = data.getUint64(headers + index * 64 + 24, .little);
          expect(
            data.getUint32(relocation + 8, .little),
            arch == .arm64 ? 257 : 1,
          );
          expect(data.getInt64(relocation + 16, .little), 0);
        }
        final truncated = Uint8List.fromList(bytes);
        ByteData.sublistView(truncated).setUint32(relocation, 16, .little);
        expect(() => format.decodeObject(truncated), throwsFormatException);
        final unaligned = Uint8List.fromList(bytes);
        ByteData.sublistView(unaligned).setUint32(relocation, 1, .little);
        expect(() => format.decodeObject(unaligned), throwsUnsupportedError);
        final addend = Uint8List.fromList(bytes);
        ByteData.sublistView(
          addend,
        ).setInt64(os == .macos ? contents + 8 : relocation + 16, 1, .little);
        expect(() => format.decodeObject(addend), throwsUnsupportedError);
      });

      test(
        '$target rejects malformed address fields at the module boundary',
        () {
          for (final section in [
            Section.code(Uint8List(8), alignment: 8),
            Section.zeroFill(8, alignment: 8),
            Section.data(Uint8List(8), alignment: 4),
            Section.data(Uint8List(7), alignment: 8),
            Section.data([1, 0, 0, 0, 0, 0, 0, 0], alignment: 8),
          ]) {
            expect(
              () => ObjectModule(
                target,
                [section],
                [],
                imports: ['value'],
                relocations: [const .address(0, 0, 0)],
              ),
              throwsArgumentError,
            );
          }
          for (final references in <List<Relocation>>[
            [const .address(-1, 0, 0)],
            [const .address(1, 0, 0)],
            [const .address(0, -8, 0)],
            [const .address(0, 1, 0)],
            [const .address(0, 16, 0)],
            [const .address(0, 0, -1)],
            [const .address(0, 0, 1)],
            [const .address(0, 0, 0), const .address(0, 0, 0)],
          ]) {
            expect(
              () => ObjectModule(
                target,
                [Section.data(Uint8List(16), alignment: 8)],
                [],
                imports: ['value'],
                relocations: references,
              ),
              throwsArgumentError,
            );
          }
        },
      );
    }
  }
}
