import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';

import 'elf.dart';
import 'mach_o.dart';

/// Writes indexed static archives for macOS and Linux.
abstract final class Archive() {
  /// Encodes matching [objects] as separate members with deterministic headers.
  ///
  /// Member names are their input indices followed by `.o`. Duplicate symbols
  /// remain in the index; an archive consumer selects the members it needs.
  static Uint8List encode(Iterable<ObjectFile> objects) {
    final members = objects.toList();
    if (members.isEmpty ||
        members.any((o) => o.target != members.first.target)) {
      throw ArgumentError('Expected non-empty objects for one target.');
    }
    final darwin = members.first.target.operatingSystem == .macos;
    final symbols = [
      for (final (i, object) in members.indexed)
        for (final symbol in object.symbols) (i, utf8.encode(symbol.name)),
    ];
    final namesSize = symbols.fold(0, (n, s) => n + s.$2.length + 1);
    final table = ByteData(
      darwin
          ? 8 + symbols.length * 8 + namesSize
          : 4 + symbols.length * 4 + namesSize,
    );
    final output = BytesBuilder(copy: false)..add(ascii.encode('!<arch>\n'));

    int member(String name, Uint8List bytes) {
      final padding = darwin ? (-bytes.length) & 7 : 0;
      final nameSize = darwin
          ? name.length + (-(output.length + 60 + name.length) & 7)
          : 0;
      final size = nameSize + bytes.length + padding;
      final field = darwin ? '#1/$nameSize' : '$name/';
      if (field.length > 16 || size > 9999999999) {
        throw UnsupportedError('Archive member exceeds the header limits.');
      }
      output.add(
        ascii.encode(
          '${field.padRight(16)}${'0'.padRight(12)}${'0'.padRight(6)}'
          '${'0'.padRight(6)}${'100644'.padRight(8)}${'$size'.padRight(10)}`\n',
        ),
      );
      if (darwin) {
        output.add(ascii.encode(name));
        output.add(Uint8List(nameSize - name.length));
      }
      final contentOffset = output.length;
      output.add(bytes);
      output.add(Uint8List(padding));
      if (output.length.isOdd) output.addByte(10);
      return contentOffset;
    }

    final tableOffset = member(
      darwin ? '__.SYMDEF' : '',
      table.buffer.asUint8List(),
    );
    final offsets = <int>[];
    for (final (i, object) in members.indexed) {
      if (output.length > 0xffffffff) {
        throw UnsupportedError('Archive requires 64-bit symbol offsets.');
      }
      offsets.add(output.length);
      member('$i.o', darwin ? MachO.encode(object) : Elf.encode(object));
    }
    table.setUint32(
      0,
      symbols.length * (darwin ? 8 : 1),
      darwin ? .little : .big,
    );
    var nameOffset = 0;
    final strings = (darwin ? 8 : 4) + symbols.length * (darwin ? 8 : 4);
    if (darwin) table.setUint32(strings - 4, namesSize, .little);
    final bytes = table.buffer.asUint8List();
    for (final (i, (memberIndex, name)) in symbols.indexed) {
      if (darwin) {
        table.setUint32(4 + i * 8, nameOffset, .little);
        table.setUint32(8 + i * 8, offsets[memberIndex], .little);
      } else {
        table.setUint32(4 + i * 4, offsets[memberIndex], .big);
      }
      bytes.setAll(strings + nameOffset, name);
      nameOffset += name.length + 1;
    }
    final archive = output.takeBytes();
    archive.setAll(tableOffset, bytes);
    return archive;
  }
}
