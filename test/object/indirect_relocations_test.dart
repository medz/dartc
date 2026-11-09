import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
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
      final List<Fixup> loads;
      final List<int> code;
      final Fixup invalid;
      final List<int> invalidCode;
      if (arch == .arm64) {
        final assembler = arm.Assembler();
        loads = [
          assembler.pageAddress(.x9),
          assembler.loadPageOffset(.x0, .x9),
        ];
        code = assembler.finish();
        final add = arm.Assembler();
        invalid = add.addPageOffset(.x0, .x0);
        invalidCode = add.finish();
      } else {
        final assembler = x64.Assembler();
        loads = [assembler.loadAddress(.rax)];
        code = assembler.finish();
        final lea = x64.Assembler();
        invalid = lea.address(.rax);
        invalidCode = lea.finish();
      }
      test('$target rejects indirect references on address calculations', () {
        expect(
          () => ObjectModule(
            target,
            [Section.code(invalidCode)],
            [],
            imports: ['value'],
            relocations: [
              Relocation.instruction(
                0,
                invalid.offset,
                invalid.encoding,
                0,
                indirect: true,
              ),
            ],
          ),
          throwsArgumentError,
        );
      });
      for (final indirect in [false, true]) {
        test(
          '$target retains load instruction and indirect=$indirect in objects',
          () {
            final original = ObjectModule(
              target,
              [Section.code(code)],
              [],
              imports: ['value'],
              relocations: [
                for (final load in loads)
                  Relocation.instruction(
                    0,
                    load.offset,
                    load.encoding,
                    0,
                    indirect: indirect,
                  ),
              ],
            );
            final bytes = format.encodeObject(original),
                data = ByteData.sublistView(bytes);
            final decoded = format.decodeObject(bytes);
            expect(decoded.sections.single.bytes, code);
            expect(decoded.imports, ['value']);
            expect(
              decoded.relocations.cast<InstructionRelocation>().map(
                (r) => (r.offset, r.encoding, r.indirect, r.symbol),
              ),
              unorderedEquals(
                original.relocations.cast<InstructionRelocation>().map(
                  (r) => (r.offset, r.encoding, r.indirect, r.symbol),
                ),
              ),
            );
            final int relocation, stride;
            final expected = <int>[];
            if (os == .macos) {
              relocation = data.getUint32(160, .little);
              stride = 8;
              expected.addAll(
                arch == .arm64
                    ? (indirect ? [0x5d, 0x6c] : [0x3d, 0x4c])
                    : [indirect ? 0x3d : 0x1d],
              );
            } else {
              final sections = data.getUint64(40, .little);
              relocation = data.getUint64(sections + 6 * 64 + 24, .little);
              stride = 24;
              expected.addAll(
                arch == .arm64
                    ? (indirect ? [311, 312] : [275, 286])
                    : [indirect ? 9 : 2],
              );
            }
            expect([
              for (var i = 0; i < expected.length; i++)
                os == .macos
                    ? data.getUint32(relocation + i * stride + 4, .little) >> 24
                    : data.getUint64(relocation + i * stride + 8, .little) &
                          0xffffffff,
            ], os == .macos ? expected.reversed : expected);
            final truncated = Uint8List.fromList(bytes);
            final broken = ByteData.sublistView(truncated);
            if (os == .macos) {
              broken.setUint32(relocation, code.length - 3, .little);
            } else {
              broken.setUint64(relocation, code.length - 3, .little);
            }
            expect(() => format.decodeObject(truncated), throwsFormatException);
            final badOpcode = Uint8List.fromList(bytes);
            final codeOffset = os == .macos
                ? data.getUint32(152, .little)
                : data.getUint64(
                    data.getUint64(40, .little) + 64 + 24,
                    .little,
                  );
            badOpcode.fillRange(codeOffset, codeOffset + code.length, 0);
            expect(
              () => format.decodeObject(badOpcode),
              throwsUnsupportedError,
            );
          },
        );
      }
    }
  }
}
