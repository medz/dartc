import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test('finalizer arrays require whole immutable pointer slots', () {
    expect(() => Section.finalizers([0]), throwsArgumentError);
    final section = Section.finalizers(Uint8List(16));
    expect(section.alignment, 8);
    expect(section.size, 16);
    expect(() => section.bytes[0] = 1, throwsUnsupportedError);
  });
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
      final code = arch == .arm64 ? [0xc0, 3, 0x5f, 0xd6] : [0xc3];
      ObjectModule module({Symbol? symbol, List<Relocation>? relocations}) =>
          ObjectModule(
            target,
            [Section.code(code), Section.finalizers(Uint8List(8))],
            [symbol ?? Symbol('cleanup', 0, 0, code.length, binding: .local)],
            relocations: relocations ?? [const Relocation.address(1, 0, 0)],
          );
      test('$target preserves finalizers and rejects malformed headers', () {
        final bytes = format.encodeObject(module());
        final decoded = format.decodeObject(bytes);
        expect(decoded.sections[1].kind, SectionKind.finalizers);
        expect(decoded.sections[1].alignment, 8);
        expect(decoded.relocations.single, isA<AddressRelocation>());
        for (final malformedSize in [false, true]) {
          final corrupt = Uint8List.fromList(bytes);
          final data = ByteData.sublistView(corrupt);
          if (os == .linux) {
            final header = data.getUint64(40, .little) + 128;
            data.setUint64(
              header + (malformedSize ? 32 : 48),
              malformedSize ? 7 : 4,
              .little,
            );
          } else {
            const header = 104 + 80;
            if (malformedSize) {
              data.setUint64(header + 40, 7, .little);
            } else {
              data.setUint32(header + 52, 2, .little);
            }
          }
          expect(() => format.decodeObject(corrupt), throwsFormatException);
        }
      });
      test(
        '$target requires a relocation to local code for every finalizer',
        () {
          expect(() => module(relocations: []), throwsArgumentError);
          expect(
            () => module(symbol: Symbol('global', 0, 0, code.length)),
            throwsArgumentError,
          );
          expect(
            () => module(
              symbol: Symbol(
                'end',
                0,
                code.length,
                null,
                kind: .unknown,
                binding: .local,
              ),
            ),
            throwsArgumentError,
          );
          expect(
            () => module(
              symbol: const Symbol(
                'data',
                1,
                0,
                8,
                kind: .data,
                binding: .local,
              ),
            ),
            throwsArgumentError,
          );
          expect(
            () => ObjectModule(
              target,
              [Section.finalizers(Uint8List(8))],
              [],
              imports: ['external'],
              relocations: [const Relocation.address(0, 0, 0)],
            ),
            throwsArgumentError,
          );
        },
      );
    }
  }
}
