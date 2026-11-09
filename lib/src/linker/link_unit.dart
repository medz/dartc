import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Coalesced storage with source bytes copied only into the final image.
final class SectionGroup(
  final SectionKind kind,
  final int size,
  final int alignment,
  final List<(int, Section)> parts,
);

/// Resolves module-local identities and groups sections for one library link.
final class LinkUnit(
  final Target target,
  Iterable<ObjectModule> input,
  final String name,
) {
  final sections = <SectionGroup>[];
  final symbols = <Symbol>[];
  final _references = <Relocation>[];

  this {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name');
    }
    final objects = input.toList();
    if (objects.isEmpty || objects.any((object) => object.target != target)) {
      throw ArgumentError('Expected non-empty modules for $target.');
    }
    final bases = [
      for (final object in objects)
        List<(int, int)?>.filled(object.sections.length, null),
    ];
    for (final kind in SectionKind.values) {
      final parts = <(int, Section)>[];
      var size = 0, alignment = 1;
      for (final (i, object) in objects.indexed) {
        for (final (j, section) in object.sections.indexed) {
          if (section.kind != kind) continue;
          size = (size + section.alignment - 1) & -section.alignment;
          RangeError.checkNotNegative(size, 'section offset');
          if (section.alignment > alignment) alignment = section.alignment;
          bases[i][j] = (sections.length, size);
          parts.add((size, section));
          size += section.size;
          RangeError.checkNotNegative(size, 'section end');
        }
      }
      if (parts.isNotEmpty) {
        sections.add(SectionGroup(kind, size, alignment, parts));
      }
    }
    final globals = <String, int>{}, symbolBases = <int>[];
    for (final (i, object) in objects.indexed) {
      symbolBases.add(symbols.length);
      for (final symbol in object.symbols) {
        if (symbol.binding == .global) {
          if (globals.containsKey(symbol.name)) {
            throw ArgumentError('Duplicate global: ${symbol.name}');
          }
          globals[symbol.name] = symbols.length;
        }
        final (section, offset) = bases[i][symbol.section]!;
        symbols.add(
          .new(
            symbol.name,
            section,
            offset + symbol.offset,
            symbol.size,
            kind: symbol.kind,
            binding: symbol.binding,
            exported: symbol.exported,
          ),
        );
      }
    }
    for (final (i, object) in objects.indexed) {
      for (final name in object.imports) {
        if (!globals.containsKey(name)) {
          throw ArgumentError('Undefined symbol: $name');
        }
      }
      for (final reference in object.relocations) {
        final destination = reference.symbol < object.symbols.length
            ? symbolBases[i] + reference.symbol
            : globals[object.imports[reference.symbol -
                  object.symbols.length]]!;
        if ((reference.encoding == .arm64Call26 ||
                reference.encoding == .x64Call32) &&
            symbols[destination].kind != .function) {
          throw ArgumentError(
            'Call targets data: ${symbols[destination].name}',
          );
        }
        final (section, offset) = bases[i][reference.section]!;
        _references.add(
          .new(
            section,
            offset + reference.offset,
            reference.encoding,
            destination,
          ),
        );
      }
    }
  }

  /// Copies initialized contents and resolves instructions at their final addresses.
  void writeSections(
    ByteData image,
    List<int> fileOffsets,
    List<int> addresses,
  ) {
    if (fileOffsets.length != sections.length ||
        addresses.length != sections.length) {
      throw ArgumentError('Expected one placement per section.');
    }
    final bytes = image.buffer.asUint8List(
      image.offsetInBytes,
      image.lengthInBytes,
    );
    for (final (i, section) in sections.indexed) {
      if (addresses[i] < 0 || addresses[i] % section.alignment != 0) {
        throw ArgumentError('Invalid section address.');
      }
      if (section.kind == .zeroFill) continue;
      RangeError.checkValueInInterval(
        fileOffsets[i],
        0,
        bytes.length - section.size,
      );
      if (fileOffsets[i] % section.alignment != 0) {
        throw ArgumentError('Invalid section file alignment.');
      }
      for (final (offset, part) in section.parts) {
        bytes.setAll(fileOffsets[i] + offset, part.bytes);
      }
    }
    for (final reference in _references) {
      final symbol = symbols[reference.symbol];
      reference.encoding.apply(
        image,
        fileOffsets[reference.section] + reference.offset,
        placeAddress: addresses[reference.section] + reference.offset,
        targetAddress: addresses[symbol.section] + symbol.offset,
      );
    }
  }
}
