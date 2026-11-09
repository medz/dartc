import 'dart:convert';
import 'dart:typed_data';

import 'reader.dart';

/// An indexed native archive whose members have not been decoded as objects.
final class Archive._(
  List<ArchiveMember> members,
  List<({String name, int member})> index,
) {
  /// The ordinary members, in file order, excluding index and name tables.
  final List<ArchiveMember> members = .unmodifiable(members);

  /// Symbol names and indices into [members], in archive index order.
  ///
  /// Repeated names are retained; member selection depends on this order.
  final List<({String name, int member})> index = .unmodifiable(index);

  /// Reads a GNU or little-endian Darwin archive and owns its immutable bytes.
  ///
  /// Checks member and index records without interpreting object contents.
  /// Malformed records throw [FormatException]; unsupported archive variants
  /// throw [UnsupportedError]. Member selection and target checks belong to
  /// the linker. Thin archives and 64-bit indices are not supported.
  factory decode(Uint8List bytes) {
    final input = ObjectReader(Uint8List.fromList(bytes).asUnmodifiableView());
    final magic = ascii.decode(input.view(0, 8));
    if (magic == '!<thin>\n') throw UnsupportedError('Thin archives.');
    input.check(magic == '!<arch>\n', 'Invalid archive magic.');
    int number(int at, int width, {int radix = 10, bool optional = false}) {
      final text = ascii.decode(input.view(at, width));
      input.check(
        text.codeUnits.every((c) => c == 32 || (c >= 48 && c < 48 + radix)),
        'Invalid archive numeric field.',
      );
      if (optional && text.trim().isEmpty) return 0;
      final value = int.tryParse(text.trim(), radix: radix);
      input.check(value != null, 'Invalid archive numeric field.');
      return value!;
    }

    final members = <ArchiveMember>[], offsets = <int, int>{};
    Uint8List? names, table;
    var darwin = false;
    for (var offset = 8; offset < bytes.length;) {
      input.view(offset, 60);
      input.check(
        input.bytes[offset + 58] == 96 && input.bytes[offset + 59] == 10,
        'Invalid archive member header.',
      );
      number(offset + 16, 12, optional: true);
      number(offset + 28, 6, optional: true);
      number(offset + 34, 6, optional: true);
      number(offset + 40, 8, radix: 8, optional: true);
      final size = number(offset + 48, 10), end = offset + 60 + size;
      input.view(offset + 60, size);
      var name = ascii.decode(input.view(offset, 16)).trimRight();
      var content = offset + 60;
      if (name.startsWith('#1/')) {
        final length = int.tryParse(name.substring(3));
        input.check(
          length != null && length > 0 && length <= size,
          'Invalid BSD archive name length.',
        );
        name = input.string(content, content + length!, fixed: true);
        final encoded = utf8.encode(name).length;
        input.check(
          input.view(content + encoded, length - encoded).every((b) => b == 0),
          'Invalid BSD archive name padding.',
        );
        content += length;
      } else if (name != '/' && name != '//') {
        if (name == '/SYM64/') {
          throw UnsupportedError('64-bit archive indices.');
        }
        if (name.startsWith('/')) {
          final index = int.tryParse(name.substring(1));
          input.check(
            names != null &&
                index != null &&
                index >= 0 &&
                index < names.length,
            'Invalid GNU archive name reference.',
          );
          final start = index!;
          input.check(
            start == 0 || names![start - 1] == 10,
            'GNU name reference is not an entry start.',
          );
          final end = names!.indexOf(10, start);
          input.check(
            end > start && names[end - 1] == 47,
            'Unterminated GNU archive name.',
          );
          name = utf8.decode(Uint8List.sublistView(names, start, end - 1));
        } else if (name.endsWith('/')) {
          name = name.substring(0, name.length - 1);
        }
      }
      input.check(
        name.isNotEmpty && !name.contains('\u0000'),
        'Invalid archive member name.',
      );
      final payload = input.view(content, end - content).asUnmodifiableView();
      if (name == '/' || name == '__.SYMDEF' || name == '__.SYMDEF SORTED') {
        input.check(table == null, 'Multiple archive symbol indices.');
        table = payload;
        darwin = name != '/';
      } else if (name == '//') {
        input.check(names == null, 'Multiple GNU archive name tables.');
        names = payload;
      } else if (name == '__.SYMDEF_64' || name == '__.SYMDEF_64 SORTED') {
        throw UnsupportedError('64-bit archive indices.');
      } else {
        offsets[offset] = members.length;
        members.add(ArchiveMember._(name, payload));
      }
      offset = end;
      if (offset.isOdd) {
        input.check(
          input.view(offset, 1).single == 10,
          'Invalid archive member padding.',
        );
        offset++;
      }
    }
    if (table == null) {
      throw UnsupportedError('Archives without a symbol index.');
    }
    final indexInput = ObjectReader(table), data = indexInput.data;
    indexInput.view(0, darwin ? 8 : 4);
    final endian = darwin ? Endian.little : Endian.big;
    final value = data.getUint32(0, endian);
    indexInput.check(
      !darwin || value % 8 == 0,
      'Invalid Darwin archive index size.',
    );
    final count = darwin ? value ~/ 8 : value, stride = darwin ? 8 : 4;
    indexInput.table(4, count, stride);
    final strings = 4 + count * stride + (darwin ? 4 : 0);
    final int stringEnd;
    if (darwin) {
      indexInput.view(strings - 4, 4);
      final size = data.getUint32(strings - 4, .little);
      indexInput.view(strings, size);
      stringEnd = strings + size;
      indexInput.check(
        table.length - stringEnd < 8 &&
            indexInput
                .view(stringEnd, table.length - stringEnd)
                .every((b) => b == 0),
        'Invalid Darwin archive index padding.',
      );
    } else {
      stringEnd = table.length;
    }
    var cursor = strings;
    final index = <({String name, int member})>[];
    for (var i = 0; i < count; i++) {
      final at = 4 + i * stride;
      final offset = data.getUint32(at + (darwin ? 4 : 0), endian);
      final member = offsets[offset];
      indexInput.check(
        member != null,
        'Archive index does not point to a member header.',
      );
      if (darwin) cursor = strings + data.getUint32(at, .little);
      indexInput.check(
        cursor >= strings && cursor < stringEnd,
        'Invalid archive symbol string index.',
      );
      final name = indexInput.string(cursor, stringEnd);
      indexInput.check(name.isNotEmpty, 'Empty archive index symbol.');
      index.add((name: name, member: member!));
      cursor += utf8.encode(name).length + 1;
    }
    if (!darwin) {
      indexInput.check(cursor == stringEnd, 'Extra GNU archive index bytes.');
    }
    return ._(members, index);
  }
}

/// A named member with immutable bytes, independent of object interpretation.
final class ArchiveMember._(
  /// The decoded archive name; it is not used as a filesystem path.
  final String name,

  /// The member payload, including any format-defined trailing padding.
  final Uint8List bytes,
);
