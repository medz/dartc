import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'code_signature.dart';
import 'imports.dart';
import 'macho_commands.dart';
import 'relocate.dart';

const _base = 0x100000000;

int _align16(int value) => (value + 15) & ~15;

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
  final entryOffset =
      code.functions[entry] ?? (throw ImageError('No entry function $entry.'));
  final externals = code.externals;
  final (bytes: constants, offsets: constantOffsets) = _pack(code.data);
  final hasData = constants.isNotEmpty;
  final textOffset = _align16(
    commandsEnd(imports: externals.isNotEmpty, constants: hasData),
  );
  final stubsOffset = textOffset + code.text.length;
  final textEnd = stubsOffset + externals.length * stubBytes;
  final constantsOffset = hasData ? _align16(textEnd) : textEnd;
  final constantsEnd = constantsOffset + constants.length;
  final slotsOffset = pageAlign(constantsEnd);
  final slots = importSlots(externals.length, pageBytes);

  final text = Uint8List.fromList(code.text);
  relocate(text, _base + textOffset, code.relocations, {
    for (final (i, name) in externals.indexed)
      name: _base + stubsOffset + i * stubBytes,
    for (final MapEntry(:key, :value) in code.functions.entries)
      key: _base + textOffset + value,
    for (final MapEntry(:key, :value) in constantOffsets.entries)
      key: _base + constantsOffset + value,
  });
  final stubs = importStubs(
    externals,
    _base + stubsOffset,
    _base + slotsOffset,
  );
  final table = externals.isEmpty
      ? Uint8List(0)
      : importTable(
          externals,
          segments: 4,
          segment: 2,
          segmentOffset: slotsOffset,
          pageBytes: pageBytes,
        );
  final linkOffset = slotsOffset + pageAlign(slots.length);
  final signatureOffset = linkOffset + _align16(table.length);

  final out = ByteWriter(.little);
  writeCommands(
    out,
    base: _base,
    textOffset: textOffset,
    textEnd: textEnd,
    constantsOffset: constantsOffset,
    constantsEnd: constantsEnd,
    entryOffset: textOffset + entryOffset,
    slotsBytes: slots.length,
    tableBytes: table.length,
    signatureOffset: signatureOffset,
    signatureBytes: codeSignatureSize(signatureOffset, identifier),
    // The identity depends on the program alone, so builds are reproducible.
    uuid: sha256
        .convert([...text, ...stubs, ...constants, ...table])
        .bytes
        .sublist(0, 16),
  );
  out
    ..align(16)
    ..bytes(text)
    ..bytes(stubs)
    ..align(hasData ? 16 : 1)
    ..bytes(constants)
    ..align(pageBytes)
    ..bytes(slots)
    ..align(pageBytes)
    ..bytes(table)
    ..align(16);
  final file = out.finish();
  final signature = codeSignature(
    file,
    identifier: identifier,
    textBytes: slotsOffset,
  );
  return Uint8List.fromList([...file, ...signature]);
}
