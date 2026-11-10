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
import 'fixtures/archives.dart';

void main() {
  // Archive records depend on the file format, not the member's CPU.
  for (final os in OperatingSystem.values) {
    final target = Target(os, .arm64), assets = NativeAssets(target);
    final ObjectFormat format = os == .macos ? MachO(target) : Elf(target);
    late final original = assets.file('linker/values.a').readAsBytesSync();

    test('$target reads members, index order and duplicate names', () {
      for (final fixture in ['values', 'calls', 'data']) {
        final archive = Archive.decode(
          assets.file('linker/$fixture.a').readAsBytesSync(),
        );
        final members = archive.members
            .map((m) => format.decodeObject(m.bytes))
            .toList();
        expect(archive.members.map((m) => m.name), ['0.o', '1.o']);
        expect(archive.index, [
          for (final (i, module) in members.indexed)
            for (final symbol in module.symbols)
              if (symbol.binding == .global) (name: symbol.name, member: i),
        ]);
      }
      final module = format.decodeObject(
        assets.file('linker/0.o').readAsBytesSync(),
      );
      final duplicate = Archive.decode(
        ArchiveWriter(format).encode([module, module]),
      );
      expect(duplicate.index, [
        (name: module.symbols.single.name, member: 0),
        (name: module.symbols.single.name, member: 1),
      ]);
    });

    test('$target owns archive bytes and exposes only immutable views', () {
      final buffer = Uint8List(original.length + 16)..setAll(8, original);
      final archive = Archive.decode(
        Uint8List.sublistView(buffer, 8, buffer.length - 8),
      );
      buffer.fillRange(0, buffer.length, 0xff);
      final module = format.decodeObject(archive.members.first.bytes);
      expect(
        format.encodeObject(module),
        assets.file('linker/0.o').readAsBytesSync(),
      );
      expect(() => archive.members.clear(), throwsUnsupportedError);
      expect(() => archive.index.clear(), throwsUnsupportedError);
      expect(() => archive.members.first.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => archive.members.first.bytes.buffer.asUint8List()[0] = 0,
        throwsUnsupportedError,
      );
    });

    test('$target rejects corrupt member and symbol records', () {
      final darwin = os == .macos, endian = darwin ? Endian.little : Endian.big;
      final table =
          68 +
          (darwin
              ? int.parse(ascii.decode(original.sublist(11, 24)).trim())
              : 0);
      final data = ByteData.sublistView(original);
      final firstOffset = data.getUint32(table + (darwin ? 8 : 4), endian);
      final strings = table + (darwin ? 24 : 12);
      final corruptions = <String, void Function(ByteData)>{
        'magic': (d) => d.setUint8(0, 0),
        'header trailer': (d) => d.setUint8(66, 0),
        'member size': (d) => d.setUint8(56, 57),
        'numeric field': (d) => d.setUint8(24, 120),
        'octal mode': (d) => d.setUint8(48, 56),
        'index count': (d) => d.setUint32(table, 0xffffffff, endian),
        'index points to metadata': (d) =>
            d.setUint32(table + (darwin ? 8 : 4), 8, endian),
        'index points to payload': (d) =>
            d.setUint32(table + (darwin ? 8 : 4), firstOffset + 60, endian),
        'empty symbol': (d) => d.setUint8(strings, 0),
        'invalid UTF-8': (d) => d.setUint8(strings, 0xff),
        'unterminated last symbol': (d) =>
            d.setUint8(strings + (darwin ? 14 : 12), 1),
        if (darwin) ...{
          'name exceeds member': (d) => d.setUint8(11, 57),
          'symbol string offset': (d) =>
              d.setUint32(table + 4, 0xffffffff, .little),
          'string size': (d) => d.setUint32(table + 20, 0xffffffff, .little),
          'nonzero index padding': (d) => d.setUint8(strings + 15, 1),
        },
      };
      for (final MapEntry(:key, :value) in corruptions.entries) {
        final bytes = Uint8List.fromList(original);
        value(ByteData.sublistView(bytes));
        expect(() => Archive.decode(bytes), throwsFormatException, reason: key);
      }
      for (final length in [0, 7, 67, original.length - 1]) {
        expect(
          () => Archive.decode(Uint8List.sublistView(original, 0, length)),
          throwsFormatException,
        );
      }
    });
  }

  test('reads GNU long names and BSD UTF-8 names without decoding members', () {
    final name = 'directory/very_long_member_name.o';
    final bytes = archiveBytes([
      ('/', [0, 0, 0, 0]),
      ('//', utf8.encode('$name/\nnext.o/\n')),
      ('/0', [1, 2, 3]),
      ('/${utf8.encode(name).length + 2}', [4]),
      ('#1/6', [...utf8.encode('猫.o'), 0, 5]),
    ]);
    final archive = Archive.decode(bytes);
    expect(archive.members.map((m) => m.name), [name, 'next.o', '猫.o']);
    expect(archive.members.map((m) => m.bytes), [
      [1, 2, 3],
      [4],
      [5],
    ]);
    expect(archive.index, isEmpty);
    bytes[bytes.length - 1] = 0;
    expect(() => Archive.decode(bytes), throwsFormatException);
  });

  test('rejects invalid names and duplicate metadata, identifies unsupported variants', () {
    for (final members in <List<(String, List<int>)>>[
      [
        ('/', [0, 0, 0, 0]),
        ('/', [0, 0, 0, 0]),
      ],
      [
        ('//', [0]),
        ('//', [0]),
      ],
      [
        ('/0', [0]),
      ],
      [
        ('//', utf8.encode('name.o/\n')),
        ('/1', [0]),
      ],
      [
        ('//', utf8.encode('name.o\n')),
        ('/0', [0]),
      ],
      for (final name in ['#1/0x3', '#1/+3', '#1/-0'])
        [
          ('/', [0, 0, 0, 0]),
          (name, [97, 0, 0]),
        ],
      for (final name in ['/0x0', '/+0', '/-0'])
        [
          ('/', [0, 0, 0, 0]),
          ('//', utf8.encode('name.o/\n')),
          (name, [1]),
        ],
      [
        ('#1/9', [0]),
      ],
      [
        ('#1/3', [97, 0, 98]),
      ],
      [
        ('#1/1', [0]),
      ],
      [
        ('/', [0, 0, 0, 0, 1]),
      ],
    ]) {
      expect(
        () => Archive.decode(archiveBytes(members)),
        throwsFormatException,
      );
    }
    for (final bytes in [
      Uint8List.fromList(ascii.encode('!<thin>\n')),
      archiveBytes([]),
      archiveBytes([
        ('a.o/', [1]),
      ]),
      archiveBytes([('/SYM64/', [])]),
      archiveBytes([('__.SYMDEF_64/', [])]),
    ]) {
      expect(() => Archive.decode(bytes), throwsUnsupportedError);
    }
    final sorted = Archive.decode(
      archiveBytes([('__.SYMDEF SORTED', List.filled(8, 0))]),
    );
    expect(sorted.members, isEmpty);
    expect(sorted.index, isEmpty);
  });
}
