import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch), assets = NativeAssets(target);
      final darwin = os == .macos;
      test(
        '$target data objects retain zero-fill storage and address references',
        () {
          final storage = assets.file('linker/data_0.o').readAsBytesSync();
          final data = ByteData.sublistView(storage);
          expect(storage.length, lessThan(0x20020));
          if (darwin) {
            expect(data.getUint32(96, .little), 3);
            const bss = 104 + 2 * 80;
            expect(data.getUint64(bss + 40, .little), 0x20020);
            expect(data.getUint32(bss + 48, .little), 0);
            expect(data.getUint32(bss + 52, .little), 5);
            expect(data.getUint32(bss + 64, .little), 1);
          } else {
            final bss = data.getUint64(40, .little) + 3 * 64;
            expect(data.getUint32(bss + 4, .little), 8);
            expect(data.getUint64(bss + 8, .little), 3);
            expect(data.getUint64(bss + 32, .little), 0x20020);
            expect(data.getUint64(bss + 48, .little), 32);
          }
          final bytes = assets.file('linker/data_1.o').readAsBytesSync();
          final code = ByteData.sublistView(bytes);
          final int symbols, strings, relocation, count;
          if (darwin) {
            final symtab = 32 + code.getUint32(36, .little) + 24;
            symbols = code.getUint32(symtab + 8, .little);
            strings = code.getUint32(symtab + 16, .little);
            relocation = code.getUint32(160, .little);
            count = code.getUint32(164, .little);
          } else {
            final sections = code.getUint64(40, .little);
            symbols = code.getUint64(sections + 3 * 64 + 24, .little);
            strings = code.getUint64(sections + 4 * 64 + 24, .little);
            final rela = sections + 7 * 64;
            expect(code.getUint32(rela + 40, .little), 3);
            expect(code.getUint32(rela + 44, .little), 1);
            relocation = code.getUint64(rela + 24, .little);
            count = code.getUint64(rela + 32, .little) ~/ 24;
          }
          final entries = <(int, String, int)>[];
          for (var i = 0; i < count; i++) {
            final offset = relocation + i * (darwin ? 8 : 24);
            final info = darwin
                ? code.getUint32(offset + 4, .little)
                : code.getUint64(offset + 8, .little);
            final index = darwin ? info & 0xffffff : info >> 32;
            final name =
                strings +
                code.getUint32(symbols + index * (darwin ? 16 : 24), .little);
            entries.add((
              code.getUint32(offset, .little),
              utf8.decode(bytes.sublist(name, bytes.indexOf(0, name))),
              darwin ? info >> 24 : info & 0xffffffff,
            ));
            if (!darwin) {
              expect(
                code.getInt64(offset + 16, .little),
                arch == .arm64 ? 0 : -4,
              );
            }
          }
          entries.sort((a, b) => a.$1.compareTo(b.$1));
          final prefix = darwin ? '_' : '';
          expect(entries.map((e) => e.$2), [
            for (final name in [
              '${prefix}constant',
              '${prefix}state',
              '${prefix}counter',
              'private_data',
            ])
              for (var i = 0; i < (arch == .arm64 ? 2 : 1); i++) name,
          ]);
          expect(entries.map((e) => e.$3), [
            for (var i = 0; i < 4; i++)
              if (arch == .arm64) ...[
                darwin ? 0x3d : 275,
                darwin ? 0x4c : 277,
              ] else
                darwin ? 0x1d : 2,
          ]);
          final archive = assets.file('linker/data.a').readAsBytesSync();
          var tableOffset = 68;
          if (darwin) {
            tableOffset += int.parse(
              ascii.decode(archive.sublist(8, 24)).trim().substring(3),
            );
          }
          final table = ByteData.sublistView(archive, tableOffset);
          final members =
              table.getUint32(0, darwin ? .little : .big) ~/ (darwin ? 8 : 1);
          expect(members, 7);
          final names =
              tableOffset + (darwin ? 8 + members * 8 : 4 + members * 4);
          final firstEnd = archive.indexOf(0, names);
          expect(
            utf8.decode(archive.sublist(names, firstEnd)),
            '${prefix}constant',
          );
        },
      );

      test(
        '$target linked data has distinct permissions and no file-backed BSS',
        () {
          final bytes = assets.library('linker/data').readAsBytesSync();
          final data = ByteData.sublistView(bytes);
          final segments = <(int, int, int, int, int)>[];
          if (darwin) {
            var cursor = 32;
            for (var i = 0; i < data.getUint32(16, .little); i++) {
              if (data.getUint32(cursor, .little) == 0x19) {
                segments.add((
                  data.getUint64(cursor + 24, .little),
                  data.getUint64(cursor + 32, .little),
                  data.getUint64(cursor + 40, .little),
                  data.getUint64(cursor + 48, .little),
                  data.getUint32(cursor + 60, .little),
                ));
              }
              cursor += data.getUint32(cursor + 4, .little);
            }
            expect(
              segments.last.$1 - segments.last.$3,
              greaterThanOrEqualTo(0x20020),
            );
          } else {
            for (var i = 0; i < data.getUint16(56, .little); i++) {
              final base = 64 + i * 56;
              if (data.getUint32(base, .little) != 1) continue;
              final flags = data.getUint32(base + 4, .little);
              final alignment = data.getUint64(base + 48, .little);
              final address = data.getUint64(base + 16, .little),
                  offset = data.getUint64(base + 8, .little);
              expect(address % alignment, offset % alignment);
              segments.add((
                address,
                data.getUint64(base + 40, .little),
                offset,
                data.getUint64(base + 32, .little),
                (flags & 4) >> 2 | (flags & 2) | (flags & 1) << 2,
              ));
            }
          }
          expect(segments.map((s) => s.$5).toSet(), {1, 3, 5});
          var end = 0;
          for (final (address, memorySize, offset, fileSize, flags)
              in segments) {
            expect(address, greaterThanOrEqualTo(end));
            expect(memorySize, greaterThanOrEqualTo(fileSize));
            expect(offset + fileSize, lessThanOrEqualTo(bytes.length));
            expect(flags & 6, isNot(6));
            if (flags == 3) {
              expect(memorySize - fileSize, greaterThanOrEqualTo(0x20020));
            }
            end = address + memorySize;
          }
        },
      );
    }
  }
}
