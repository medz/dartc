import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'code_signature.dart';
import 'imports.dart';
import 'macho_commands.dart';
import 'relocate.dart';

const _base = 0x100000000;

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
  final textOffset = (commandsEnd(imports: externals.isNotEmpty) + 15) & ~15;
  final stubsOffset = textOffset + code.text.length;
  final textEnd = stubsOffset + externals.length * stubBytes;
  final slotsOffset = pageAlign(textEnd);
  final slots = importSlots(externals.length, pageBytes);

  final text = Uint8List.fromList(code.text);
  relocate(text, _base + textOffset, code.relocations, {
    for (final (i, name) in externals.indexed)
      name: _base + stubsOffset + i * stubBytes,
    for (final MapEntry(:key, :value) in code.functions.entries)
      key: _base + textOffset + value,
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
  final signatureOffset = linkOffset + ((table.length + 15) & ~15);

  final out = ByteWriter(.little);
  writeCommands(
    out,
    base: _base,
    textOffset: textOffset,
    textEnd: textEnd,
    entryOffset: textOffset + entryOffset,
    slotsBytes: slots.length,
    tableBytes: table.length,
    signatureOffset: signatureOffset,
    signatureBytes: codeSignatureSize(signatureOffset, identifier),
    // The identity depends on the program alone, so builds are reproducible.
    uuid: sha256.convert([...text, ...stubs, ...table]).bytes.sublist(0, 16),
  );
  out
    ..align(16)
    ..bytes(text)
    ..bytes(stubs)
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
