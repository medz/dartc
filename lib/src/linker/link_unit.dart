import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import 'input.dart';
import 'linkage_table.dart';

/// Coalesced storage with source bytes copied only into the final image.
final class SectionGroup(
  final SectionKind kind,
  final int size,
  final int alignment,
  final List<(int, Section)> parts,
);

/// Resolves module-local identities and groups sections for one library link.
final class LinkUnit(
  ObjectFormat format,
  Iterable<LinkInput> input,
  final String name, {
  String? entry,
}) {
  final Target target = format.target;
  final sections = <SectionGroup>[];
  final symbols = <Symbol>[];
  final libraries = <String>[];
  final bindings = <({int library, String name, int slot, SymbolKind kind})>[];
  final rebases = <({int slot, int target})>[];
  final _references = <Relocation>[];

  this {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name');
    }
    final objects = <ObjectModule>[], globals = <String, (int, int)>{};
    final missing = <String>{?entry}, loaded = <Archive, Set<int>>{};
    void include(ObjectModule object) {
      if (object.target != target) {
        throw ArgumentError('Expected an object for $target.');
      }
      for (final (j, symbol) in object.symbols.indexed) {
        if (symbol.binding != .global) continue;
        if (globals.containsKey(symbol.name)) {
          throw ArgumentError('Duplicate global: ${symbol.name}');
        }
        globals[symbol.name] = (objects.length, j);
        missing.remove(symbol.name);
      }
      objects.add(object);
      for (final name in object.imports) {
        if (!globals.containsKey(name)) missing.add(name);
      }
    }

    void includeMember(Archive archive, int member, String name) {
      if (!(loaded[archive] ??= {}).add(member)) {
        throw FormatException('Loaded archive member does not define $name.');
      }
      final module = format.decodeObject(archive.members[member].bytes);
      if (!module.symbols.any((s) => s.binding == .global && s.name == name)) {
        throw FormatException('Archive index member does not define $name.');
      }
      include(module);
    }

    void search(Iterable<Archive> archives) {
      var previous = -1;
      while (previous != objects.length) {
        previous = objects.length;
        if (target.operatingSystem == .linux) {
          for (final archive in archives) {
            for (final (:name, :member) in archive.index) {
              if (missing.contains(name)) includeMember(archive, member, name);
            }
          }
        } else {
          nextName:
          for (final name in missing.toList()) {
            if (globals.containsKey(name)) continue;
            for (final archive in archives) {
              for (final entry in archive.index) {
                if (entry.name != name) continue;
                includeMember(archive, entry.member, name);
                continue nextName;
              }
            }
          }
        }
      }
    }

    final archives = <Archive>[];
    final imports = <String, (int, String)>{};
    for (final entry in input) {
      switch (entry) {
        case ObjectInput(:final module):
          include(module);
        case ArchiveInput(:final archive):
          if (target.operatingSystem == .linux) {
            search([archive]);
          } else {
            archives.add(archive);
          }
        case SharedLibraryInput(:final name, :final symbols):
          var library = libraries.indexOf(name);
          if (library < 0) {
            library = libraries.length;
            libraries.add(name);
          }
          for (final entry in symbols.entries) {
            final binding = (library, entry.value);
            if (imports[entry.key] case final previous?
                when previous != binding) {
              throw ArgumentError('Conflicting library binding: ${entry.key}');
            }
            imports[entry.key] = binding;
          }
      }
    }
    if (target.operatingSystem == .macos) search(archives);
    final dynamicSlots = <String, int>{};
    for (final name in missing) {
      if (imports.containsKey(name)) dynamicSlots[name] = dynamicSlots.length;
    }
    missing.removeAll(dynamicSlots.keys);
    if (missing.isNotEmpty) {
      throw ArgumentError('Undefined symbol: ${missing.first}');
    }
    if (objects.isEmpty) {
      throw ArgumentError('Expected at least one included object.');
    }
    (int, int)? resolve(int owner, int index) {
      final object = objects[owner];
      return index < object.symbols.length
          ? (owner, index)
          : globals[object.imports[index - object.symbols.length]];
    }

    final staticSlots = <(int, int), int>{}, calls = <String>{};
    for (final (i, object) in objects.indexed) {
      for (final reference in object.relocations) {
        final resolved = resolve(i, reference.symbol);
        if (reference.indirect) {
          if (resolved != null) {
            staticSlots.putIfAbsent(
              resolved,
              () => dynamicSlots.length + staticSlots.length,
            );
          }
        } else if (resolved == null) {
          final name = object.imports[reference.symbol - object.symbols.length];
          if (reference.encoding != .arm64Call26 &&
              reference.encoding != .x64Call32) {
            throw UnsupportedError(
              'Shared-library addresses require indirect references: $name',
            );
          }
          calls.add(name);
        }
      }
    }
    final table = objects.length,
        slotCount = dynamicSlots.length + staticSlots.length;
    if (slotCount != 0) {
      include(
        linkageTable(target, slotCount, {
          for (final entry in dynamicSlots.entries)
            if (calls.contains(entry.key)) entry.key: entry.value,
        }),
      );
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
    final symbolBases = <int>[];
    for (final (i, object) in objects.indexed) {
      symbolBases.add(symbols.length);
      for (final symbol in object.symbols) {
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
    for (final MapEntry(key: name, value: slot) in dynamicSlots.entries) {
      final (library, symbol) = imports[name]!;
      bindings.add((
        library: library,
        name: symbol,
        slot: symbolBases[table] + slot,
        kind: calls.contains(name) ? .function : .unknown,
      ));
    }
    for (final MapEntry(key: (owner, index), value: slot)
        in staticSlots.entries) {
      rebases.add((
        slot: symbolBases[table] + slot,
        target: symbolBases[owner] + index,
      ));
    }
    for (final (i, object) in objects.indexed) {
      for (final reference in object.relocations) {
        final resolved = resolve(i, reference.symbol);
        final dynamicSlot = reference.symbol < object.symbols.length
            ? null
            : dynamicSlots[object.imports[reference.symbol -
                  object.symbols.length]];
        final (owner, index) = reference.indirect
            ? (table, dynamicSlot ?? staticSlots[resolved]!)
            : resolved!;
        final definition = objects[owner].symbols[index];
        final storage = objects[owner].sections[definition.section];
        if ((reference.encoding == .arm64Call26 ||
                reference.encoding == .x64Call32) &&
            (definition.kind == .data ||
                storage.kind != .code ||
                definition.offset == storage.size)) {
          throw ArgumentError(
            'Call target is outside code: ${definition.name}',
          );
        }
        final (section, offset) = bases[i][reference.section]!;
        _references.add(
          .new(
            section,
            offset + reference.offset,
            reference.encoding,
            symbolBases[owner] + index,
          ),
        );
      }
    }
  }

  /// Resolves an executable entry to a global definition in code storage.
  Symbol entryPoint(String name) {
    final symbol = symbols
        .where((s) => s.name == name && s.binding == .global)
        .firstOrNull;
    if (symbol == null ||
        symbol.kind == .data ||
        sections[symbol.section].kind != .code ||
        target.architecture == .arm64 && symbol.offset % 4 != 0 ||
        symbol.offset >= sections[symbol.section].size) {
      throw ArgumentError(
        'Entry must name a defined global code symbol: $name',
      );
    }
    return symbol;
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
    for (final rebase in rebases) {
      final slot = symbols[rebase.slot], target = symbols[rebase.target];
      image.setUint64(
        fileOffsets[slot.section] + slot.offset,
        addresses[target.section] + target.offset,
        .little,
      );
    }
  }
}
