import 'dart:typed_data';

import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'elf_headers.dart';
import 'elf_layout.dart';
import 'elf_machine.dart';
import 'elf_symbols.dart';
import 'pack.dart';
import 'relocate.dart';

/// What programs can find functions of C in, like with the official runtime.
const _libraries = ['libc.so.6', 'libm.so.6'];

/// Builds a Linux executable.
///
/// [entry] is where the system starts it. External functions are bound to the
/// system libraries then.
Uint8List linkElf(EmittedCode code, {required String entry}) =>
    _ElfImage(code, entry: entry).build();

/// Builds a Linux library that programs load as [name].
Uint8List linkElfLibrary(EmittedCode code, {required String name}) =>
    _ElfImage(code, name: name).build();

final class _ElfImage(
  final EmittedCode code, {
  final String? entry,
  final String? name,
}) {
  late final machine = ElfMachine.of(code.architecture);
  final names = ElfNames();

  late final constants = packParts({
    ...code.data,
    for (final MapEntry(key: name, value: entries) in code.tables.entries)
      name: Uint8List(entries.length * 4),
  });
  late final constObjects = packObjects(code, writable: false);
  late final data = packObjects(code, writable: true);

  late final _imported = code.externals;
  late final _exported = code.exports.keys.toList();
  late final _references = [
    for (final object in code.objects.values) ...object.references.keys,
  ].length;

  /// The sections that the file tells about, in order.
  late final _sections = [
    if (entry != null) '.interp',
    '.hash',
    '.dynsym',
    '.dynstr',
    '.rela.dyn',
    '.rodata',
    '.text',
    '.dynamic',
    '.got',
    '.data.rel.ro',
    '.data',
    '.shstrtab',
  ];

  int _section(String name) => _sections.indexOf(name) + 1;

  List<ElfSymbol> _symbols(Map<String, int> addresses) => [
    for (final name in _imported)
      (name: name, type: .none, section: 0, value: 0, isGlobal: true),
    for (final name in _exported)
      (
        name: name,
        type: .function,
        section: _section('.text'),
        value: addresses[code.exports[name]] ?? 0,
        isGlobal: true,
      ),
  ];

  late final _nameBytes = () {
    for (final library in _libraries) {
      names[library];
    }
    if (name case final name?) names[name];
    encodeElfSymbols(_symbols(const {}), names);
    return names.finish();
  }();

  late final Uint8List _interpreter = Uint8List.fromList([
    ...machine.interpreter.codeUnits,
    0,
  ]);

  late final hash = elfHashTable([..._imported, ..._exported]);

  late final layout = ElfLayout(
    pageBytes: machine.pageBytes,
    stubBytes: machine.stubBytes,
    headerBytes: ElfHeaders.fileBytes + _segmentCount * ElfHeaders.segmentBytes,
    tables: {
      if (entry != null) 'interp': _interpreter.length,
      'hash': hash.length,
      'dynsym': (_imported.length + _exported.length + 1) * elfSymbolBytes,
      'dynstr': _nameBytes.length,
      'rela': (_imported.length + _references) * ElfHeaders.relocationBytes,
    },
    constantBytes: constants.bytes.length,
    codeBytes: code.text.length,
    importCount: _imported.length,
    dynamicBytes: _dynamicEntries(null).length * 16,
    constObjectBytes: constObjects.bytes.length,
    dataBytes: data.bytes.length,
  );

  bool get _hasData => data.bytes.isNotEmpty;

  int get _segmentCount => (entry == null ? 6 : 8) + (_hasData ? 1 : 0);

  late final Map<String, int> addresses = {
    for (final (i, name) in _imported.indexed)
      name: layout['stubs'].address + i * machine.stubBytes,
    for (final (offsets, part) in [
      (code.functions, 'text'),
      (constants.offsets, 'constants'),
      (constObjects.offsets, 'constObjects'),
      (data.offsets, 'data'),
    ])
      for (final MapEntry(:key, :value) in offsets.entries)
        key: layout[part].address + value,
  };

  /// What tells the loader about the tables, where [layout] says.
  List<(int, int)> _dynamicEntries(ElfLayout? layout) {
    const needed = 1, hash = 4, strings = 5, symbols = 6, relocations = 7;
    const relocationsSize = 8, relocationSize = 9, stringsSize = 10;
    const symbolSize = 11, soname = 14, debug = 21, flags = 30;
    const moreFlags = 0x6ffffffb, bindNow = 8, now = 1, isProgram = 0x8000000;
    int at(String part) => layout?[part].address ?? 0;
    int size(String part) => layout?[part].bytes ?? 0;
    return [
      for (final library in _libraries) (needed, names[library]),
      if (name case final name?) (soname, names[name]),
      (hash, at('hash')),
      (strings, at('dynstr')),
      (symbols, at('dynsym')),
      (stringsSize, size('dynstr')),
      (symbolSize, elfSymbolBytes),
      (relocations, at('rela')),
      (relocationsSize, size('rela')),
      (relocationSize, ElfHeaders.relocationBytes),
      (flags, bindNow),
      (moreFlags, now | (entry == null ? 0 : isProgram)),
      if (entry != null) (debug, 0),
      (0, 0),
    ];
  }

  Uint8List _dynamic() {
    final out = ByteWriter(.little);
    for (final (tag, value) in _dynamicEntries(layout)) {
      out
        ..u64(tag)
        ..u64(value);
    }
    return out.finish();
  }

  /// What the loader fills in: import slots, and references between objects.
  Uint8List _relocations() {
    final out = ByteWriter(.little);
    void add(int address, int type, int symbol, int value) => out
      ..u64(address)
      ..u64(symbol << 32 | type)
      ..u64(value);
    for (var i = 0; i < _imported.length; i++) {
      add(layout['slots'].address + i * 8, machine.slotRelocation, i + 1, 0);
    }
    code.objects.forEach((name, object) {
      object.references.forEach((word, target) {
        add(
          addresses[name]! + word,
          machine.baseRelocation,
          0,
          addresses[target] ?? (throw ImageError('No symbol $target.')),
        );
      });
    });
    return out.finish();
  }

  Uint8List _text() {
    final text = Uint8List.fromList(code.text);
    relocate(text, layout['text'].address, code.relocations, addresses);
    return text;
  }

  Uint8List _constants() {
    final bytes = constants.bytes;
    code.tables.forEach((name, entries) {
      fillTable(bytes, constants.offsets[name]!, name, entries, addresses);
    });
    return bytes;
  }

  Uint8List build() {
    final contents = {
      if (entry != null) 'interp': _interpreter,
      'hash': hash,
      'dynsym': encodeElfSymbols(_symbols(addresses), names),
      'dynstr': _nameBytes,
      'rela': _relocations(),
      'constants': _constants(),
      'text': _text(),
      'stubs': machine.stubs(
        _imported,
        layout['stubs'].address,
        layout['slots'].address,
      ),
      'dynamic': _dynamic(),
      'slots': Uint8List(_imported.length * 8),
      'constObjects': constObjects.bytes,
      'data': data.bytes,
    };
    final out = ByteWriter(.little);
    final sectionNames = ElfNames();
    for (final name in _sections) {
      sectionNames[name];
    }
    final nameBytes = sectionNames.finish();
    final namesAt = layout['data'].end;
    final sectionsAt = (namesAt + nameBytes.length + 7) ~/ 8 * 8;
    writeElfHeader(
      out,
      type: 3,
      machine: machine.number,
      entry: switch (entry) {
        null => 0,
        final entry =>
          addresses[entry] ?? (throw ImageError('No entry function $entry.')),
      },
      segments: _segmentCount,
      sectionsAt: sectionsAt,
      sections: _sections.length + 1,
    );
    _writeSegments(out);
    contents.forEach((name, bytes) {
      out
        ..zeros(layout[name].offset - out.length)
        ..bytes(bytes);
    });
    out
      ..bytes(nameBytes)
      ..align(8);
    _writeSections(out, sectionNames, namesAt, nameBytes.length);
    return out.finish();
  }

  void _writeSegments(ByteWriter out) {
    const load = 1, dynamic = 2, interpreter = 3, headers = 6;
    const stack = 0x6474e551, constantAfter = 0x6474e552;
    const execute = 1, write = 2, read = 4;
    void segment(int type, int flags, ElfPart part, {int? memory, int? align}) {
      writeElfSegment(
        out,
        type: type,
        flags: flags,
        offset: part.offset,
        address: part.address,
        fileBytes: part.bytes,
        memoryBytes: memory ?? part.bytes,
        alignment: align ?? machine.pageBytes,
      );
    }

    final constantBytes = layout.constantEnd - layout.constant.address;
    if (entry != null) {
      const start = ElfHeaders.fileBytes;
      final bytes = _segmentCount * ElfHeaders.segmentBytes;
      segment(headers, read, ElfPart(start, start, bytes), align: 8);
      segment(interpreter, read, layout['interp'], align: 1);
    }
    segment(load, read, layout.headers);
    segment(load, read | execute, layout.code);
    segment(load, read | write, layout.constant, memory: constantBytes);
    // Nothing loads a segment without bytes.
    if (_hasData) segment(load, read | write, layout.data);
    segment(dynamic, read | write, layout['dynamic'], align: 8);
    segment(stack, read | write, ElfPart(0, 0, 0), align: 16);
    segment(
      constantAfter,
      read,
      layout.constant,
      memory: constantBytes,
      align: 1,
    );
  }

  void _writeSections(ByteWriter out, ElfNames names, int at, int bytes) {
    const program = 1, strings = 3, relocations = 4, hash = 5, dynamic = 6;
    const symbols = 11, write = 1, allocate = 2, execute = 4;
    out.zeros(ElfHeaders.sectionBytes);
    void section(
      String name,
      int type,
      int flags,
      ElfPart part, {
      int link = 0,
      int info = 0,
      int entryBytes = 0,
      int alignment = 16,
    }) => writeElfSection(
      out,
      name: names[name],
      type: type,
      flags: flags,
      address: part.address,
      offset: part.offset,
      bytes: part.bytes,
      link: link,
      info: info,
      entryBytes: entryBytes,
      alignment: alignment,
    );
    final dynamicSymbols = _section('.dynsym');
    final dynamicNames = _section('.dynstr');
    if (entry != null) {
      section('.interp', program, allocate, layout['interp'], alignment: 1);
    }
    section('.hash', hash, allocate, layout['hash'], link: dynamicSymbols);
    section(
      '.dynsym',
      symbols,
      allocate,
      layout['dynsym'],
      link: dynamicNames,
      info: 1,
      entryBytes: elfSymbolBytes,
    );
    section('.dynstr', strings, allocate, layout['dynstr'], alignment: 1);
    section(
      '.rela.dyn',
      relocations,
      allocate,
      layout['rela'],
      link: dynamicSymbols,
      entryBytes: ElfHeaders.relocationBytes,
    );
    section('.rodata', program, allocate, layout['constants']);
    section('.text', program, allocate | execute, layout.code);
    section(
      '.dynamic',
      dynamic,
      allocate | write,
      layout['dynamic'],
      link: dynamicNames,
      entryBytes: 16,
    );
    section('.got', program, allocate | write, layout['slots']);
    final objects = layout['constObjects'];
    section('.data.rel.ro', program, allocate | write, objects);
    section('.data', program, allocate | write, layout.data);
    section('.shstrtab', strings, 0, ElfPart(at, 0, bytes), alignment: 1);
  }
}
