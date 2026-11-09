@Tags(['assets'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch), assets = NativeAssets(target);
      test(
        '$target object calls reference reordered local and undefined symbols',
        () {
          for (var module = 0; module < 2; module++) {
            final bytes = assets
                .file('linker/call_$module.o')
                .readAsBytesSync();
            final data = ByteData.sublistView(bytes);
            final first = module == 0;
            if (os == .macos) {
              final relocation = data.getUint32(160, .little);
              expect(data.getUint32(164, .little), 1);
              final info = data.getUint32(relocation + 4, .little);
              expect(info >> 24, 0x2d);
              expect(info & 0xffffff, first ? 2 : 0);
              final symbols = data.getUint32(216, .little);
              final strings = data.getUint32(224, .little);
              expect(data.getUint32(244, .little), 1); // One local definition.
              expect(data.getUint32(252, .little), 1); // One global definition.
              expect(data.getUint32(260, .little), first ? 1 : 0);
              expect(data.getUint8(symbols + 4), 0xe);
              expect(data.getUint8(symbols + 16 + 4), first ? 0xf : 0x1f);
              if (first) {
                expect(data.getUint8(symbols + 32 + 4), 1);
                final name = strings + data.getUint32(symbols + 32, .little);
                expect(
                  utf8.decode(bytes.sublist(name, bytes.indexOf(0, name))),
                  '_helper',
                );
              }
            } else {
              final sections = data.getUint64(40, .little);
              final relocation = data.getUint64(
                sections + 6 * 64 + 24,
                .little,
              );
              expect(
                data.getUint32(sections + 6 * 64 + 4, .little),
                4,
              ); // SHT_RELA.
              expect(
                data.getUint32(sections + 6 * 64 + 40, .little),
                2,
              ); // Symbol table.
              expect(
                data.getUint32(sections + 6 * 64 + 44, .little),
                1,
              ); // Code section.
              expect(data.getUint64(sections + 6 * 64 + 32, .little), 24);
              final info = data.getUint64(relocation + 8, .little);
              expect(info >> 32, first ? 3 : 1);
              expect(info & 0xffffffff, arch == .arm64 ? 283 : (first ? 4 : 2));
              expect(
                data.getInt64(relocation + 16, .little),
                arch == .arm64 ? 0 : -4,
              );
              final symbols = data.getUint64(sections + 2 * 64 + 24, .little);
              expect(data.getUint32(sections + 2 * 64 + 44, .little), 2);
              expect(
                data.getUint8(symbols + 24 + 4),
                2,
              ); // STB_LOCAL | STT_FUNC.
              expect(
                data.getUint8(symbols + 48 + 5),
                first ? 0 : 2,
              ); // Visibility.
              if (first) {
                expect(
                  data.getUint16(symbols + 72 + 6, .little),
                  0,
                ); // SHN_UNDEF.
                final strings = data.getUint64(sections + 3 * 64 + 24, .little);
                final name = strings + data.getUint32(symbols + 72, .little);
                expect(
                  utf8.decode(bytes.sublist(name, bytes.indexOf(0, name))),
                  'helper',
                );
              }
            }
          }
        },
      );
    }
  }
}
