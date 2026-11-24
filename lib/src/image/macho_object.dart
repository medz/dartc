import 'dart:typed_data';

import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'layout.dart';
import 'pack.dart';
import 'relocate.dart';
import 'symbols.dart';

// Kinds of relocations.
const _unsigned = 0, _subtractor = 1, _branch = 2, _page = 3, _pageOffset = 4;

/// A section of an object file.
final class _Section(
  final String name,
  final String segment,
  final Uint8List bytes, {
  final int flags = 0,
}) {
  final relocations = ByteWriter(.little);
  int address = 0, offset = 0, relocationOffset = 0;

  int get relocationCount => relocations.length ~/ 8;

  void relocate(
    int at,
    int symbol,
    int kind, {
    required int length,
    bool isRelative = false,
  }) => relocations
    ..u32(at)
    ..u32(
      symbol | (isRelative ? 1 : 0) << 24 | length << 25 | 1 << 27 | kind << 28,
    );
}

/// Builds an object file for linkers, of [code] that exports functions.
Uint8List writeMachoObject(EmittedCode code) => _ObjectWriter(code).write();

final class _ObjectWriter(final EmittedCode code) {
  /// Functions of the system whose addresses are used. Only code can refer to
  /// those, so each gets some that goes there.
  late final _taken = {
    for (final Relocation(:kind, :symbol) in code.relocations)
      if (kind != RelocationKind.call26 && code.externals.contains(symbol))
        symbol,
  }.toList();

  late final constants = packParts({
    ...code.data,
    for (final MapEntry(key: name, value: entries) in code.tables.entries)
      name: Uint8List(entries.length * 4),
  });
  late final constObjects = packObjects(code, writable: false);
  late final data = packObjects(code, writable: true);

  late final _text = _Section(
    '__text',
    '__TEXT',
    Uint8List.fromList([...code.text, ...Uint8List(_taken.length * 4)]),
    flags: 0x80000400,
  );
  late final _sections = [
    _text,
    _Section('__const', '__TEXT', constants.bytes),
    _Section('__const', '__DATA', constObjects.bytes),
    _Section('__data', '__DATA', data.bytes),
  ];

  /// The symbols, local ones first and undefined ones last.
  late final List<MachoSymbol> _symbols = _findSymbols();
  late final _numbers = {
    for (final (i, symbol) in _symbols.indexed) symbol.name: i,
  };

  static String _stub(String name) => 'l.stub.$name';

  /// What local symbols are called, which linkers leave out.
  static String _local(String name) => 'l$name';

  List<MachoSymbol> _findSymbols() {
    final parts = [
      {
        ...code.functions,
        for (final (i, name) in _taken.indexed)
          _stub(name).substring(1): code.text.length + i * 4,
      },
      constants.offsets,
      constObjects.offsets,
      data.offsets,
    ];
    MachoSymbol symbol(
      String name,
      int section,
      int address, {
      bool isExternal = false,
    }) => (
      name: name,
      section: section,
      address: address,
      isExternal: isExternal,
    );
    return [
      for (final (i, offsets) in parts.indexed)
        for (final MapEntry(key: name, value: offset) in offsets.entries)
          symbol(_local(name), i + 1, _sections[i].address + offset),
      for (final MapEntry(key: name, value: function) in code.exports.entries)
        symbol('_$name', 1, code.functions[function]!, isExternal: true),
      for (final name in code.externals)
        symbol('_$name', 0, 0, isExternal: true),
    ];
  }

  int _number(String name) =>
      _numbers[_local(name)] ??
      _numbers['_$name'] ??
      (throw ImageError('No symbol $name.'));

  void _place(int headerBytes) {
    var address = 0;
    for (final section in _sections) {
      address = align16(address);
      section
        ..address = address
        ..offset = headerBytes + address;
      address += section.bytes.length;
    }
  }

  void _addRelocations() {
    // Linkers expect what comes last first.
    for (final Relocation(:offset, :kind, :symbol)
        in code.relocations.reversed) {
      final isTaken = kind != RelocationKind.call26 && _taken.contains(symbol);
      final number = isTaken ? _numbers[_stub(symbol)]! : _number(symbol);
      _text.relocate(
        offset,
        number,
        switch (kind) {
          .call26 => _branch,
          .page21 => _page,
          .pageOffset12 => _pageOffset,
        },
        length: 2,
        isRelative: kind != .pageOffset12,
      );
    }
    final words = ByteData.sublistView(_text.bytes);
    for (final (i, name) in _taken.indexed) {
      final at = code.text.length + i * 4;
      words.setUint32(at, 0x14000000, .little);
      _text.relocate(at, _number(name), _branch, length: 2, isRelative: true);
    }
    code.tables.forEach((name, functions) {
      for (final (i, function) in functions.indexed) {
        final at = constants.offsets[name]! + i * 4;
        _sections[1]
          ..relocate(at, _number(name), _subtractor, length: 2)
          ..relocate(at, _number(function), _unsigned, length: 2);
      }
    });
    for (final (section, offsets) in [
      (_sections[2], constObjects.offsets),
      (_sections[3], data.offsets),
    ]) {
      offsets.forEach((name, start) {
        code.objects[name]!.references.forEach((word, target) {
          section.relocate(start + word, _number(target), _unsigned, length: 3);
        });
      });
    }
  }

  Uint8List write() {
    final commandBytes = 72 + 80 * _sections.length + 24 + 24 + 80;
    _place(align16(32 + commandBytes));
    _addRelocations();
    final last = _sections.last;
    final contentBytes = last.address + last.bytes.length;
    var at = (_sections.first.offset + contentBytes + 7) & ~7;
    for (final section in _sections) {
      section.relocationOffset = at;
      at += section.relocations.length;
    }
    final (:symbols, :names) = encodeSymbols(_symbols);
    final out = ByteWriter(.little)
      ..u32(0xfeedfacf)
      ..u32(0x0100000c) // ARM64.
      ..u32(0)
      ..u32(1) // An object.
      ..u32(4)
      ..u32(commandBytes)
      ..u32(0)
      ..u32(0);
    _writeSegment(out, contentBytes);
    _writeTables(out, symbolOffset: at, namesBytes: names.length);
    for (final section in _sections) {
      out
        ..zeros(section.offset - out.length)
        ..bytes(section.bytes);
    }
    out.align(8);
    for (final section in _sections) {
      out.bytes(section.relocations.finish());
    }
    out
      ..bytes(symbols)
      ..bytes(names);
    return out.finish();
  }

  void _writeSegment(ByteWriter out, int bytes) {
    out
      ..u32(0x19) // LC_SEGMENT_64, without a name.
      ..u32(72 + 80 * _sections.length)
      ..zeros(16)
      ..u64(0)
      ..u64(bytes)
      ..u64(_sections.first.offset)
      ..u64(bytes)
      ..u32(7)
      ..u32(7)
      ..u32(_sections.length)
      ..u32(0);
    for (final section in _sections) {
      out
        ..text(section.name, 16)
        ..text(section.segment, 16)
        ..u64(section.address)
        ..u64(section.bytes.length)
        ..u32(section.offset)
        ..u32(4)
        ..u32(section.relocationCount == 0 ? 0 : section.relocationOffset)
        ..u32(section.relocationCount)
        ..u32(section.flags)
        ..zeros(12);
    }
  }

  void _writeTables(
    ByteWriter out, {
    required int symbolOffset,
    required int namesBytes,
  }) {
    final external = code.exports.length, undefined = code.externals.length;
    final local = _symbols.length - external - undefined;
    out
      ..u32(0x32) // LC_BUILD_VERSION: macOS 11, no tools.
      ..u32(24)
      ..u32(1)
      ..u32(11 << 16)
      ..u32(11 << 16)
      ..u32(0)
      ..u32(0x2) // LC_SYMTAB.
      ..u32(24)
      ..u32(symbolOffset)
      ..u32(_symbols.length)
      ..u32(symbolOffset + _symbols.length * symbolBytes)
      ..u32(namesBytes)
      ..u32(0xb) // LC_DYSYMTAB.
      ..u32(80)
      ..u32(0)
      ..u32(local)
      ..u32(local)
      ..u32(external)
      ..u32(local + external)
      ..u32(undefined)
      ..zeros(48);
  }
}
