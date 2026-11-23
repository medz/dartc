import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/emit.dart';

import 'bytes.dart';
import 'code_signature.dart';

/// Code that cannot become an executable: always a compiler bug.
final class ImageError(final String message) implements Exception {
  @override
  String toString() => 'ImageError: $message';
}

const _pageBytes = 0x4000, _base = 0x100000000;
const _loader = '/usr/lib/dyld', _system = '/usr/lib/libSystem.B.dylib';

/// Builds a signed macOS ARM64 executable.
///
/// [entry] takes no arguments; the low 8 bits of its result become the
/// process exit code. [identifier] names the program in its signature.
Uint8List linkMacho(
  EmittedCode code, {
  required String entry,
  required String identifier,
}) {
  final entryOffset =
      code.functions[entry] ?? (throw ImageError('No entry function $entry.'));
  final textOffset = (_Layout.commandsEnd + 15) & ~15;
  final text = _relocate(code, _base + textOffset);
  final layout = _Layout(
    textOffset: textOffset,
    textBytes: text.length,
    entryOffset: entryOffset,
    identifier: identifier,
  );
  // The identity depends on the program alone, so builds are reproducible.
  final uuid = sha256.convert(text).bytes.sublist(0, 16);
  final out = ByteWriter(.little);
  layout.writeCommands(out, uuid);
  out
    ..align(16)
    ..bytes(text)
    ..align(_pageBytes);
  final file = out.finish();
  return (ByteWriter(.little)
        ..bytes(file)
        ..bytes(
          codeSignature(
            file,
            identifier: identifier,
            textBytes: layout.segmentBytes,
          ),
        ))
      .finish();
}

/// Copies the code with every symbol address filled in.
Uint8List _relocate(EmittedCode code, int address) {
  final text = Uint8List.fromList(code.text);
  final words = ByteData.sublistView(text);
  for (final Relocation(:offset, :kind, :symbol) in code.relocations) {
    final found =
        code.functions[symbol] ?? (throw ImageError('No symbol $symbol.'));
    final target = address + found, at = address + offset;
    final word = words.getUint32(offset, .little);
    final bits = switch (kind) {
      .call26 => _signed((target - at) >> 2, 26, symbol),
      .page21 => _pageBitsOf((target >> 12) - (at >> 12), symbol),
      .pageOffset12 => (target & 0xfff) << 10,
    };
    words.setUint32(offset, word | bits, .little);
  }
  return text;
}

int _pageBitsOf(int pages, String symbol) {
  final field = _signed(pages, 21, symbol);
  return (field & 3) << 29 | (field >> 2) << 5;
}

int _signed(int value, int bits, String symbol) {
  final limit = 1 << (bits - 1);
  if (value < -limit || value >= limit) {
    throw ImageError('$symbol is out of reach.');
  }
  return value & ((1 << bits) - 1);
}

/// File positions and the load commands describing them.
final class _Layout({
  required final int textOffset,
  required final int textBytes,
  required final int entryOffset,
  required final String identifier,
}) {
  static const _segment = 72, _section = 80;
  static const _loaderBytes = 32, _systemBytes = 56;
  static const _commandBytes =
      3 * _segment +
      _section +
      24 +
      80 +
      _loaderBytes +
      24 +
      24 +
      24 +
      _systemBytes +
      16;
  static const commandsEnd = 32 + _commandBytes;

  /// The executable segment; the signature follows it in the file.
  int get segmentBytes =>
      (textOffset + textBytes + _pageBytes - 1) & ~(_pageBytes - 1);

  int get _signatureBytes => codeSignatureSize(segmentBytes, identifier);

  void writeCommands(ByteWriter out, List<int> uuid) {
    out
      ..u32(0xfeedfacf)
      ..u32(0x0100000c) // ARM64.
      ..u32(0)
      ..u32(2) // An executable.
      ..u32(11)
      ..u32(_commandBytes)
      ..u32(0x200085) // No undefined symbols, dyld, two-level, PIE.
      ..u32(0);
    _writeSegment(out, '__PAGEZERO', 0, _base, 0, 0, 0);
    _writeSegment(out, '__TEXT', _base, segmentBytes, 0, segmentBytes, 5);
    _writeTextSection(out);
    _writeSegment(
      out,
      '__LINKEDIT',
      _base + segmentBytes,
      (_signatureBytes + _pageBytes - 1) & ~(_pageBytes - 1),
      segmentBytes,
      _signatureBytes,
      1,
    );
    out
      ..u32(0x2) // LC_SYMTAB, empty.
      ..u32(24)
      ..zeros(16)
      ..u32(0xb) // LC_DYSYMTAB, empty.
      ..u32(80)
      ..zeros(72)
      ..u32(0xe) // LC_LOAD_DYLINKER.
      ..u32(_loaderBytes)
      ..u32(12)
      ..text(_loader, _loaderBytes - 12)
      ..u32(0x1b) // LC_UUID.
      ..u32(24)
      ..bytes(uuid)
      ..u32(0x32) // LC_BUILD_VERSION: macOS 11, no tools.
      ..u32(24)
      ..u32(1)
      ..u32(11 << 16)
      ..u32(11 << 16)
      ..u32(0)
      ..u32(0x80000028) // LC_MAIN.
      ..u32(24)
      ..u64(textOffset + entryOffset)
      ..u64(0)
      ..u32(0xc) // LC_LOAD_DYLIB.
      ..u32(_systemBytes)
      ..u32(24)
      ..u32(2)
      ..u32(1 << 16)
      ..u32(1 << 16)
      ..text(_system, _systemBytes - 24)
      ..u32(0x1d) // LC_CODE_SIGNATURE.
      ..u32(16)
      ..u32(segmentBytes)
      ..u32(_signatureBytes);
    if (out.length != commandsEnd) {
      throw StateError('Load commands end at ${out.length}.');
    }
  }

  void _writeSegment(
    ByteWriter out,
    String name,
    int address,
    int memoryBytes,
    int fileOffset,
    int fileBytes,
    int protection,
  ) {
    final sections = name == '__TEXT' ? 1 : 0;
    out
      ..u32(0x19)
      ..u32(_segment + sections * _section)
      ..text(name, 16)
      ..u64(address)
      ..u64(memoryBytes)
      ..u64(fileOffset)
      ..u64(fileBytes)
      ..u32(protection)
      ..u32(protection)
      ..u32(sections)
      ..u32(0);
  }

  void _writeTextSection(ByteWriter out) {
    out
      ..text('__text', 16)
      ..text('__TEXT', 16)
      ..u64(_base + textOffset)
      ..u64(textBytes)
      ..u32(textOffset)
      ..u32(4) // 16-byte alignment.
      ..u32(0)
      ..u32(0)
      ..u32(0x80000400) // Only instructions.
      ..zeros(12);
  }
}
