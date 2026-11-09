import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/addresses.dart';
import 'fixtures/functions.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final Linker linker = os == .macos
          ? MachOLinker(target)
          : ElfLinker(target);
      for (final executable in [false, true]) {
        test(
          '$target absolute addresses and protection, executable=$executable',
          () {
            final entry = functions(target, {'entry': 0});
            final inputs = <LinkInput>[
              .object(entry),
              .object(constantAddressTable(target)),
            ];
            final image = executable
                ? linker.linkExecutable(
                    inputs,
                    entry: entry.symbols.single.name,
                  )
                : linker.linkSharedLibrary(inputs, name: 'addresses');
            final data = ByteData.sublistView(image);
            int? address, offset;
            if (os == .macos) {
              var cursor = 32;
              for (var i = 0; i < data.getUint32(16, .little); i++) {
                if (data.getUint32(cursor, .little) == 0x19 &&
                    ascii.decode(image.sublist(cursor + 8, cursor + 20)) ==
                        '__DATA_CONST') {
                  expect(data.getUint32(cursor + 60, .little), 3);
                  expect(data.getUint32(cursor + 68, .little), 0x10);
                  address = data.getUint64(cursor + 72 + 32, .little);
                  offset = data.getUint32(cursor + 72 + 48, .little);
                }
                cursor += data.getUint32(cursor + 4, .little);
              }
            } else {
              final headers = data.getUint64(40, .little);
              // Code is followed by the read-only data section.
              address = data.getUint64(headers + 2 * 64 + 16, .little);
              offset = data.getUint64(headers + 2 * 64 + 24, .little);
              var relro = false;
              for (var i = 0; i < data.getUint16(56, .little); i++) {
                final at = 64 + i * 56, type = data.getUint32(at, .little);
                if (type == 0x6474e552) {
                  relro = true;
                  expect(
                    data.getUint64(at + 16, .little),
                    lessThanOrEqualTo(address),
                  );
                  expect(
                    data.getUint64(at + 16, .little) +
                        data.getUint64(at + 40, .little),
                    greaterThanOrEqualTo(address + 24),
                  );
                }
                if (type == 1 && data.getUint64(at + 8, .little) == offset) {
                  expect(data.getUint32(at + 4, .little), executable ? 4 : 6);
                }
              }
              expect(relro, !executable);
            }
            expect(offset, isNotNull);
            expect(data.getUint64(offset!, .little), address! + 16);
            expect(data.getUint64(offset + 8, .little), address);
            expect(data.getUint64(offset + 16, .little), 37);
          },
        );
      }
    }
  }
}
