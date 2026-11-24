import 'dart:typed_data';

import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'elf_headers.dart';
import 'elf_machine.dart';
import 'elf_symbols.dart';
import 'pack.dart';
import 'relocate.dart';

// What sections are for.
const _write = 1, _allocate = 2, _execute = 4;

/// A section of an object file.
final class _Section(
  final String name,
  final Uint8List bytes,
  final int flags,
) {
  final relocations = ByteWriter(.little);

  void relocate(int at, int type, int symbol, int addend) => relocations
    ..u64(at)
    ..u64(symbol << 32 | type)
    ..u64(addend);
}

/// Builds an object file for linkers, of [code] that exports functions.
Uint8List writeElfObject(EmittedCode code) => _ElfObject(code).write();

final class _ElfObject(final EmittedCode code) {
  late final machine = ElfMachine.of(code.architecture);

  /// Functions of the system whose addresses are used. Only code can refer to
  /// those, so each gets some that goes there.
  late final _taken = {
    for (final Relocation(:kind, :symbol) in code.relocations)
      if (!kind.isCall && code.externals.contains(symbol)) symbol,
  }.toList();

  late final constants = packParts({
    ...code.data,
    for (final MapEntry(key: name, value: entries) in code.tables.entries)
      name: Uint8List(entries.length * 4),
  });
  late final constObjects = packObjects(code, writable: false);
  late final data = packObjects(code, writable: true);

  late final _sections = [
    _Section(
      '.text',
      Uint8List.fromList([
        ...code.text,
        for (final _ in _taken) ...machine.jump,
      ]),
      _allocate | _execute,
    ),
    _Section('.rodata', constants.bytes, _allocate),
    _Section('.data.rel.ro', constObjects.bytes, _allocate | _write),
    _Section('.data', data.bytes, _allocate | _write),
  ];

  /// Where each own symbol is: the number of its section, from 1 on, and the
  /// offset there.
  late final _places = {
    for (final (i, offsets) in [
      code.functions,
      constants.offsets,
      constObjects.offsets,
      data.offsets,
    ].indexed)
      for (final MapEntry(:key, :value) in offsets.entries) key: (i + 1, value),
  };

  late final _exported = code.exports.keys.toList();

  /// The symbols after those of the sections, which have the numbers of these.
  List<ElfSymbol> get _symbols => [
    for (final name in _exported)
      (
        name: name,
        type: .function,
        section: 1,
        value: code.functions[code.exports[name]]!,
        isGlobal: true,
      ),
    for (final name in code.externals)
      (name: name, type: .none, section: 0, value: 0, isGlobal: true),
  ];

  /// The symbol and what is added to its address, for what is called [name].
  (int, int) _target(String name) {
    if (_places[name] case final place?) return place;
    final index = code.externals.indexOf(name);
    if (index < 0) throw ImageError('No symbol $name.');
    return (_sections.length + 1 + _exported.length + index, 0);
  }

  void _relocate() {
    final [text, rodata, constant, data] = _sections;
    int jumpAt(String name) =>
        code.text.length + _taken.indexOf(name) * machine.jump.length;
    for (final Relocation(:offset, :kind, :symbol) in code.relocations) {
      final isTaken = !kind.isCall && _taken.contains(symbol);
      final (number, addend) = isTaken ? (1, jumpAt(symbol)) : _target(symbol);
      text.relocate(
        offset,
        machine.relocations[kind]!,
        number,
        addend + machine.addend,
      );
    }
    for (final name in _taken) {
      text.relocate(
        jumpAt(name) + machine.jumpOffset,
        machine.jumpRelocation,
        _target(name).$1,
        machine.addend,
      );
    }
    code.tables.forEach((name, functions) {
      for (final (i, function) in functions.indexed) {
        final at = constants.offsets[name]! + i * 4;
        final (number, addend) = _target(function);
        // The distance is from the start of the table.
        rodata.relocate(at, machine.distanceRelocation, number, addend + i * 4);
      }
    });
    code.objects.forEach((name, object) {
      final section = object.writable ? data : constant;
      final start = _places[name]!.$2;
      object.references.forEach((word, target) {
        final (number, addend) = _target(target);
        final type = machine.absoluteRelocation;
        section.relocate(start + word, type, number, addend);
      });
    });
  }

  Uint8List _symbolTable(ElfNames names) {
    final symbols = ByteWriter(.little)..zeros(elfSymbolBytes);
    for (var i = 0; i < _sections.length; i++) {
      symbols
        ..u32(0)
        ..u8(3) // The symbol of a section.
        ..u8(0)
        ..u16(i + 1)
        ..zeros(16);
    }
    symbols.bytes(encodeElfSymbols(_symbols, names).sublist(elfSymbolBytes));
    return symbols.finish();
  }

  Uint8List write() {
    _relocate();
    final names = ElfNames(), sectionNames = ElfNames();
    final symbols = _symbolTable(names);
    final out = ByteWriter(.little)..zeros(ElfHeaders.fileBytes);
    final headers = ByteWriter(.little)..zeros(ElfHeaders.sectionBytes);
    void section(
      String name,
      int type,
      Uint8List bytes, {
      int flags = 0,
      int link = 0,
      int info = 0,
      int entryBytes = 0,
    }) {
      out.align(16);
      writeElfSection(
        headers,
        name: sectionNames[name],
        type: type,
        flags: flags,
        address: 0,
        offset: out.length,
        bytes: bytes.length,
        alignment: bytes.isEmpty ? 1 : 16,
        link: link,
        info: info,
        entryBytes: entryBytes,
      );
      out.bytes(bytes);
    }

    const program = 1, table = 2, strings = 3, relocations = 4, linked = 0x40;
    final symbolsNumber = _sections.length * 2 + 2;
    for (final own in _sections) {
      section(own.name, program, own.bytes, flags: own.flags);
    }
    for (final (i, own) in _sections.indexed) {
      section(
        '.rela${own.name}',
        relocations,
        own.relocations.finish(),
        flags: linked,
        link: symbolsNumber,
        info: i + 1,
        entryBytes: ElfHeaders.relocationBytes,
      );
    }
    // The stack is not for code.
    section('.note.GNU-stack', program, Uint8List(0));
    section(
      '.symtab',
      table,
      symbols,
      link: symbolsNumber + 1,
      info: _sections.length + 1,
      entryBytes: elfSymbolBytes,
    );
    section('.strtab', strings, names.finish());
    sectionNames['.shstrtab'];
    section('.shstrtab', strings, sectionNames.finish());
    out.align(8);
    final header = ByteWriter(.little);
    writeElfHeader(
      header,
      type: 1,
      machine: machine.number,
      entry: 0,
      segments: 0,
      sectionsAt: out.length,
      sections: symbolsNumber + 3,
    );
    out.bytes(headers.finish());
    return out.finish()..setAll(0, header.finish());
  }
}
