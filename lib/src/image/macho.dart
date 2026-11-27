import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'code_signature.dart';
import 'exports.dart';
import 'fixups.dart';
import 'imports.dart';
import 'layout.dart';
import 'link_tables.dart';
import 'macho_commands.dart';
import 'pack.dart';
import 'relocate.dart';
import 'symbols.dart';

const _base = 0x100000000;

/// The contents of an image, before addresses are filled in.
final class _Contents(final EmittedCode code, final MachoKind kind) {
  late final constants = packParts({
    ...code.data,
    for (final MapEntry(key: name, value: entries) in code.tables.entries)
      name: Uint8List(entries.length * 4),
  });
  late final constObjects = packObjects(code, writable: false);
  late final data = packObjects(code, writable: true);

  late final layout = () {
    final hasImports = code.externals.isNotEmpty;
    final hasFixups =
        hasImports ||
        code.objects.values.any((object) => object.references.isNotEmpty);
    final end = commandsEnd(
      kind,
      hasConstants: constants.bytes.isNotEmpty,
      hasImports: hasImports,
      hasConstObjects: constObjects.bytes.isNotEmpty,
      hasData: data.bytes.isNotEmpty,
      hasFixups: hasFixups,
    );
    return MachoLayout(
      textOffset: align16(end),
      codeBytes: code.text.length,
      importCount: code.externals.length,
      constantBytes: constants.bytes.length,
      constObjectBytes: constObjects.bytes.length,
      dataBytes: data.bytes.length,
      hasFixups: hasFixups,
      hasZeroPage: kind is MachoExecutable,
    );
  }();

  /// Where each symbol is, from the base address.
  late final symbols = {
    for (final (i, name) in code.externals.indexed)
      name: layout.stubsOffset + i * arm64StubBytes,
    for (final (offsets, start) in [
      (code.functions, layout.textOffset),
      (constants.offsets, layout.constantsOffset),
      (constObjects.offsets, layout.constObjectsOffset),
      (data.offsets, layout.dataOffset),
    ])
      for (final MapEntry(:key, :value) in offsets.entries) key: start + value,
  };

  /// The words that objects at [offsets] refer with, after [start] bytes.
  Map<int, Fixup> references(Map<String, int> offsets, int start) => {
    for (final MapEntry(key: name, value: at) in offsets.entries)
      for (final MapEntry(key: word, value: target)
          in code.objects[name]!.references.entries)
        start + at + word: Rebase(symbols[target]!),
  };

  /// The segments with fixups, linked.
  late final fixed = [
    if (layout.hasDataConst)
      FixedSegment(
        number: layout.firstData,
        offset: layout.dataConstOffset,
        bytes:
            (ByteWriter(.little)
                  ..zeros(layout.constObjectsOffset - layout.dataConstOffset)
                  ..bytes(constObjects.bytes)
                  ..align(pageBytes))
                .finish(),
        fixups: {
          for (var i = 0; i < layout.importCount; i++) i * 8: Bind(i),
          ...references(
            constObjects.offsets,
            layout.constObjectsOffset - layout.dataConstOffset,
          ),
        },
      )..link(pageBytes),
    if (layout.hasData)
      FixedSegment(
        number: layout.firstData + (layout.hasDataConst ? 1 : 0),
        offset: layout.dataOffset,
        bytes:
            (ByteWriter(.little)
                  ..bytes(data.bytes)
                  ..align(pageBytes))
                .finish(),
        fixups: references(data.offsets, 0),
      )..link(pageBytes),
  ];

  /// The loader's table of fixups.
  late final table = layout.hasFixups
      ? fixupTable(
          code.externals,
          [
            for (final segment in fixed)
              if (segment.fixups.isNotEmpty) segment,
          ],
          segments: layout.segments,
          pageBytes: pageBytes,
        )
      : Uint8List(0);

  /// The code, with every address filled in.
  late final text = () {
    final text = Uint8List.fromList(code.text);
    relocate(text, layout.textOffset, code.relocations, symbols);
    return text;
  }();
}

/// Builds a signed macOS ARM64 executable.
///
/// [entry] takes the number of arguments and their address, if anything; the
/// low 8 bits of its result become the process exit code. [identifier] names
/// the program in its signature. External functions are bound to the system
/// library when it starts. With [namesFunctions], tools like profilers find the
/// name of every function.
Uint8List linkMacho(
  EmittedCode code, {
  required String entry,
  required String identifier,
  bool namesFunctions = false,
}) => _link(code, MachoExecutable(entry), identifier, namesFunctions);

/// Builds a signed macOS ARM64 library that programs load as [name].
Uint8List linkMachoLibrary(
  EmittedCode code, {
  required String name,
  required String identifier,
  bool namesFunctions = false,
}) => _link(code, MachoLibrary(name), identifier, namesFunctions);

Uint8List _link(
  EmittedCode code,
  MachoKind kind,
  String identifier,
  bool namesFunctions,
) {
  final contents = _Contents(code, kind);
  final layout = contents.layout, symbols = contents.symbols;
  final (bytes: constants, offsets: constantOffsets) = contents.constants;
  code.tables.forEach((name, entries) {
    fillTable(constants, constantOffsets[name]!, name, entries, symbols);
  });
  final stubs = arm64Stubs(
    code.externals,
    layout.stubsOffset,
    layout.dataConstOffset,
  );
  final base = kind is MachoExecutable ? _base : 0;
  final exported = {
    for (final MapEntry(key: name, value: function) in code.exports.entries)
      '_$name': symbols[function]!,
  };
  final local = [
    if (namesFunctions)
      for (final name in code.functionNames)
        (
          name: name,
          section: 1,
          address: base + symbols[name]!,
          isExternal: false,
        ),
  ];
  final links = LinkTables(
    contents.table,
    exportTable(exported),
    encodeSymbols([
      ...local,
      for (final MapEntry(key: name, value: address) in exported.entries)
        (name: name, section: 1, address: base + address, isExternal: true),
    ]),
    local.length + exported.length,
    localCount: local.length,
  );
  final signatureOffset = layout.linkOffset + align16(links.bytes.length);
  final body = ByteWriter(.little)
    ..bytes(contents.text)
    ..bytes(stubs)
    ..zeros(layout.constantsOffset - layout.textEnd)
    ..bytes(constants)
    ..zeros(layout.dataConstOffset - layout.constantsEnd);
  for (final segment in contents.fixed) {
    body.bytes(segment.bytes);
  }
  body
    ..bytes(links.bytes)
    ..zeros(signatureOffset - layout.linkOffset - links.bytes.length);
  final bytes = body.finish();

  final out = ByteWriter(.little);
  writeCommands(
    out,
    kind,
    layout,
    links,
    base: base,
    entryOffset: switch (kind) {
      MachoExecutable(:final entry) =>
        symbols[entry] ?? (throw ImageError('No entry function $entry.')),
      MachoLibrary() => 0,
    },
    signatureOffset: signatureOffset,
    signatureBytes: codeSignatureSize(signatureOffset, identifier),
    // The identity depends on the program alone, so builds are reproducible.
    uuid: sha256.convert(bytes).bytes.sublist(0, 16),
  );
  out
    ..align(16)
    ..bytes(bytes);
  final file = out.finish();
  final signature = codeSignature(
    file,
    identifier: identifier,
    textBytes: layout.dataConstOffset,
    isMain: kind is MachoExecutable,
  );
  return Uint8List.fromList([...file, ...signature]);
}
