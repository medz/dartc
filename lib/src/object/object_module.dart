import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'symbol.dart';
import 'relocation.dart';
import 'section.dart';

/// Immutable sections, scoped definitions and unresolved symbol references.
final class ObjectModule(
  final Target target,
  Iterable<Section> sections,
  Iterable<Symbol> symbols, {
  Iterable<String> imports = const [],
  Iterable<Relocation> relocations = const [],
}) {
  /// The sections addressed by symbols and relocation sites.
  final List<Section> sections = .unmodifiable(sections);

  /// Definitions indexed by their module-local identity.
  final List<Symbol> symbols = .unmodifiable(symbols);

  /// Undefined global symbols, indexed after [symbols].
  final List<String> imports = .unmodifiable(imports);

  /// References that a linker must resolve.
  final List<Relocation> relocations = .unmodifiable(relocations);

  this {
    for (final section in this.sections) {
      if (target.architecture == .arm64 &&
          section.kind == .code &&
          (section.size % 4 != 0 || section.alignment < 4)) {
        throw ArgumentError(
          'AArch64 code requires aligned, whole instructions.',
        );
      }
    }
    final names = <String>{};
    for (final symbol in this.symbols) {
      RangeError.checkValidIndex(symbol.section, this.sections, 'section');
      final section = this.sections[symbol.section];
      if (symbol.name.isEmpty ||
          symbol.name.contains('\u0000') ||
          symbol.binding == .global && !names.add(symbol.name) ||
          symbol.exported && symbol.binding != .global ||
          symbol.offset < 0 ||
          symbol.size != null && symbol.size! <= 0 ||
          symbol.offset > section.size - (symbol.size ?? 0) ||
          symbol.kind == .function && section.kind != .code ||
          symbol.kind == .function &&
              target.architecture == .arm64 &&
              (symbol.offset % 4 != 0 || (symbol.size ?? 0) % 4 != 0)) {
        throw ArgumentError('Invalid symbol: ${symbol.name}');
      }
    }
    for (final name in this.imports) {
      if (name.isEmpty || name.contains('\u0000') || !names.add(name)) {
        throw ArgumentError('Invalid or duplicate import: $name');
      }
    }
    final sites = this.relocations.toList()
      ..sort(
        (a, b) => a.section == b.section
            ? a.offset.compareTo(b.offset)
            : a.section.compareTo(b.section),
      );
    final ends = List.filled(this.sections.length, 0);
    for (final reference in sites) {
      RangeError.checkValidIndex(reference.section, this.sections, 'section');
      final section = this.sections[reference.section];
      final offset = reference.offset;
      final width = reference is AddressRelocation ? 8 : 4;
      if (offset < ends[reference.section] ||
          offset > section.size - width ||
          reference.symbol < 0 ||
          reference.symbol >= this.symbols.length + this.imports.length) {
        throw ArgumentError('Invalid relocation at $offset.');
      }
      ends[reference.section] = offset + width;
      if (reference is AddressRelocation) {
        if ((section.kind != .data && section.kind != .readOnlyData) ||
            section.alignment < 8 ||
            offset % 8 != 0 ||
            ByteData.sublistView(section.bytes).getUint64(offset, .little) !=
                0) {
          throw ArgumentError('Invalid address relocation at $offset.');
        }
        continue;
      }
      reference as InstructionRelocation;
      final encoding = reference.encoding;
      final call = encoding == .arm64Call26 || encoding == .x64Call32;
      if (encoding.architecture != target.architecture ||
          (!call &&
              encoding != .arm64Page21 &&
              encoding != .arm64PageOffset12 &&
              encoding != .arm64LoadPageOffset12 &&
              encoding != .x64Address32 &&
              encoding != .x64LoadAddress32) ||
          reference.indirect &&
              encoding != .arm64Page21 &&
              encoding != .arm64LoadPageOffset12 &&
              encoding != .x64LoadAddress32 ||
          section.kind != .code) {
        throw ArgumentError('Invalid relocation at $offset.');
      }
      if (call && reference.symbol < this.symbols.length) {
        final definition = this.symbols[reference.symbol];
        final storage = this.sections[definition.section];
        if (definition.kind == .data ||
            storage.kind != .code ||
            definition.offset == storage.size) {
          throw ArgumentError(
            'Call target is outside code: ${definition.name}',
          );
        }
      }
      encoding.validate(
        ByteData.sublistView(section.bytes),
        offset,
        unresolved: true,
      );
    }
  }
}
