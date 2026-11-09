@Tags(['assets'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch), darwin = os == .macos;
      final assets = NativeAssets(target);

      test(
        '$target objects identify their target and reject other formats',
        () {
          final bytes = assets.file('linker/0.o').readAsBytesSync();
          final data = ByteData.sublistView(bytes);
          if (darwin) {
            expect(data.getUint32(0, .little), 0xfeedfacf);
            expect(
              data.getUint32(4, .little),
              arch == .arm64 ? 0x100000c : 0x1000007,
            );
            expect(data.getUint32(12, .little), 1);
          } else {
            expect(bytes.take(4), [0x7f, 0x45, 0x4c, 0x46]);
            expect(data.getUint16(16, .little), 1);
            expect(data.getUint16(18, .little), arch == .arm64 ? 183 : 62);
          }
          final object = ObjectModule(target, [], []);
          expect(
            () => darwin
                ? Elf(target).encodeObject(object)
                : MachO(target).encodeObject(object),
            throwsArgumentError,
          );
        },
      );

      test('$target archive index points to complete object members', () {
        final bytes = assets.file('linker/values.a').readAsBytesSync();
        expect(ascii.decode(bytes.sublist(0, 8)), '!<arch>\n');
        final members = <(int, String, Uint8List)>[];
        for (var offset = 8; offset < bytes.length;) {
          expect(ascii.decode(bytes.sublist(offset + 58, offset + 60)), '`\n');
          final size = int.parse(
            ascii.decode(bytes.sublist(offset + 48, offset + 58)).trim(),
          );
          var name = ascii.decode(bytes.sublist(offset, offset + 16)).trim();
          var payload = offset + 60;
          if (name.startsWith('#1/')) {
            final length = int.parse(name.substring(3));
            name = ascii
                .decode(bytes.sublist(payload, payload + length))
                .replaceAll('\u0000', '');
            payload += length;
            expect(payload % 8, 0);
          } else if (name != '/') {
            name = name.substring(0, name.length - 1);
          }
          members.add((
            offset,
            name,
            Uint8List.sublistView(bytes, payload, offset + 60 + size),
          ));
          offset += 60 + size + size % 2;
        }
        expect(members.map((m) => m.$2), [
          darwin ? '__.SYMDEF' : '/',
          '0.o',
          '1.o',
        ]);
        for (var i = 0; i < 2; i++) {
          final object = assets.file('linker/$i.o').readAsBytesSync();
          final member = members[i + 1].$3;
          expect(member.take(object.length), object);
          expect(member.length - object.length, lessThan(darwin ? 8 : 1));
          expect(member.skip(object.length), everyElement(0));
        }
        final table = members.first.$3, data = ByteData.sublistView(table);
        final endian = darwin ? Endian.little : Endian.big;
        final count = data.getUint32(0, endian) ~/ (darwin ? 8 : 1);
        expect(count, 2);
        final strings = darwin ? 8 + count * 8 : 4 + count * 4;
        var stringOffset = strings;
        for (var i = 0; i < count; i++) {
          if (darwin) {
            stringOffset = strings + data.getUint32(4 + i * 8, endian);
          }
          final end = table.indexOf(0, stringOffset);
          final symbol = utf8.decode(table.sublist(stringOffset, end));
          expect(symbol, '${darwin ? '_' : ''}${i == 0 ? 'first' : 'second'}');
          expect(
            data.getUint32(darwin ? 8 + i * 8 : 4 + i * 4, endian),
            members[i + 1].$1,
          );
          stringOffset = end + 1;
        }
      });
    }
  }
}
