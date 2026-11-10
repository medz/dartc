import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'object_module.dart';
import 'relocation.dart';
import 'section.dart';
import 'symbol.dart';

/// Bounded views and disjoint file regions for one object decode.
final class ObjectReader(final Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  final _regions = <(int, int)>[];

  void check(bool condition, String message) {
    if (!condition) throw FormatException(message);
  }

  Uint8List view(int offset, int size) {
    check(
      offset >= 0 &&
          offset <= bytes.length &&
          size >= 0 &&
          size <= bytes.length - offset,
      'Object range exceeds the input.',
    );
    return Uint8List.sublistView(bytes, offset, offset + size);
  }

  void region(int offset, int size) {
    view(offset, size);
    if (size != 0) _regions.add((offset, offset + size));
  }

  void table(int offset, int count, int stride) {
    check(
      offset >= 0 &&
          offset <= bytes.length &&
          count >= 0 &&
          count <= (bytes.length - offset) ~/ stride,
      'Invalid object table bounds.',
    );
    region(offset, count * stride);
  }

  int u64(int offset) {
    final value = data.getUint64(offset, .little);
    if (value < 0) throw UnsupportedError('Object values above 2^63-1.');
    return value;
  }

  void alignment(int value, int offset) {
    check(
      value > 0 && value & (value - 1) == 0 && offset % value == 0,
      'Invalid object alignment.',
    );
  }

  String string(int offset, int end, {bool fixed = false}) {
    view(offset, end - offset);
    var zero = bytes.indexOf(0, offset);
    if (zero < 0 || zero >= end) {
      check(fixed, 'Unterminated object string.');
      zero = end;
    }
    return utf8.decode(Uint8List.sublistView(bytes, offset, zero));
  }

  ObjectModule finish(
    Target target,
    List<Section> sections,
    List<Symbol> symbols,
    List<String> imports,
    List<Relocation> relocations,
  ) {
    _regions.sort((a, b) => a.$1.compareTo(b.$1));
    var end = 0;
    for (final (start, next) in _regions) {
      check(start >= end, 'Overlapping object file regions.');
      end = next;
    }
    for (final reference in relocations) {
      final section = sections[reference.section];
      if (reference is AddressRelocation) {
        check(
          reference.offset >= 0 && reference.offset <= section.size - 8,
          'Invalid object address relocation site.',
        );
        if ((section.kind != .data &&
                section.kind != .readOnlyData &&
                section.kind != .finalizers) ||
            section.alignment < 8 ||
            reference.offset % 8 != 0 ||
            ByteData.sublistView(section.bytes)
                    .getUint64(reference.offset, .little) !=
                0) {
          throw UnsupportedError(
            'Address relocation storage or implicit addend.',
          );
        }
        continue;
      }
      reference as InstructionRelocation;
      if (section.kind != .code) {
        throw UnsupportedError('Relocations outside instruction sections.');
      }
      check(
        reference.offset >= 0 &&
            reference.offset <= section.size - 4 &&
            (target.architecture != .arm64 || reference.offset % 4 == 0),
        'Invalid object relocation site.',
      );
      try {
        reference.encoding.validate(
          ByteData.sublistView(section.bytes),
          reference.offset,
          unresolved: true,
        );
      } on ArgumentError {
        throw UnsupportedError(
          'Relocation instruction form or implicit addend.',
        );
      }
    }
    try {
      return ObjectModule(
        target,
        sections,
        symbols,
        imports: imports,
        relocations: relocations,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid object contents: ${error.message}');
    }
  }
}
