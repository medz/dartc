import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'code_signature.dart';
import 'fixups.dart';
import 'imports.dart';
import 'layout.dart';
import 'macho_commands.dart';
import 'relocate.dart';

const _base = 0x100000000;

/// Joins [data], with the offset of each part.
({Uint8List bytes, Map<String, int> offsets}) _pack(
  Map<String, Uint8List> data,
) {
  final out = ByteWriter(.little), offsets = <String, int>{};
  for (final MapEntry(key: name, value: bytes) in data.entries) {
    out.align(16);
    offsets[name] = out.length;
    out.bytes(bytes);
  }
  return (bytes: out.finish(), offsets: offsets);
}

/// The contents of an executable, before addresses are filled in.
final class _Contents(final EmittedCode code) {
  late final constants = _pack({
    ...code.data,
    for (final MapEntry(key: name, value: entries) in code.tables.entries)
      name: Uint8List(entries.length * 4),
  });
  late final constObjects = _objects(writable: false);
  late final data = _objects(writable: true);

  ({Uint8List bytes, Map<String, int> offsets}) _objects({
    required bool writable,
  }) => _pack({
    for (final MapEntry(key: name, value: object) in code.objects.entries)
      if (object.writable == writable) name: object.bytes,
  });

  late final layout = () {
    final hasConstObjects = constObjects.bytes.isNotEmpty;
    final hasImports = code.externals.isNotEmpty;
    final hasFixups =
        hasImports ||
        code.objects.values.any((object) => object.references.isNotEmpty);
    final end = commandsEnd(
      hasConstants: constants.bytes.isNotEmpty,
      hasImports: hasImports,
      hasConstObjects: hasConstObjects,
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
    );
  }();

  /// Where each symbol is, from the base address.
  late final symbols = {
    for (final (i, name) in code.externals.indexed)
      name: layout.stubsOffset + i * stubBytes,
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
        number: 2,
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
        number: layout.hasDataConst ? 3 : 2,
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
/// [entry] takes no arguments; the low 8 bits of its result become the
/// process exit code. [identifier] names the program in its signature.
/// External functions are bound to the system library when it starts.
Uint8List linkMacho(
  EmittedCode code, {
  required String entry,
  required String identifier,
}) {
  final contents = _Contents(code);
  final layout = contents.layout, symbols = contents.symbols;
  final entryOffset =
      code.functions[entry] ?? (throw ImageError('No entry function $entry.'));
  final (bytes: constants, offsets: constantOffsets) = contents.constants;
  code.tables.forEach((name, entries) {
    fillTable(constants, constantOffsets[name]!, name, entries, symbols);
  });
  final stubs = importStubs(
    code.externals,
    layout.stubsOffset,
    layout.dataConstOffset,
  );
  final table = contents.table;
  final signatureOffset = layout.linkOffset + align16(table.length);
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
    ..bytes(table)
    ..zeros(signatureOffset - layout.linkOffset - table.length);
  final bytes = body.finish();

  final out = ByteWriter(.little);
  writeCommands(
    out,
    layout,
    base: _base,
    entryOffset: layout.textOffset + entryOffset,
    tableBytes: table.length,
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
  );
  return Uint8List.fromList([...file, ...signature]);
}
