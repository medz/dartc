import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/artifact.dart';

import 'code_signature.dart';
import 'export_trie.dart';

/// Encodes a Mach-O dynamic library without undefined references or fixups.
final class MachODylibLayout(
  @override final ObjectModule module,
  final String installName,
) implements ImageLayout {
  late final List<int> _name;
  late final int _idSize;
  late final int _commandsSize;
  @override
  late final int codeOffset;

  @override
  int get codeAddress => codeOffset;

  this {
    if (module.target.operatingSystem != .macos ||
        installName.isEmpty ||
        installName.contains('\u0000')) {
      throw ArgumentError('Invalid Mach-O image configuration.');
    }
    _name = utf8.encode(installName);
    _idSize = (24 + _name.length + 1 + 7) & ~7;
    _commandsSize = 152 + 72 + _idSize + 56 + 24 + 24 + 24 + 80 + 16 + 16;
    codeOffset = (32 + _commandsSize + 15) & ~15;
  }

  /// Encodes code using the section placement established by this layout.
  Uint8List encode(Uint8List code) {
    final object = module, textOffset = codeOffset;
    final symbols = object.symbols.where((s) => s.exported).toList();
    final page = object.target.architecture == .arm64 ? 16384 : 4096;
    final textSize = (textOffset + object.code.length + page - 1) & -page;
    final strings = <int>[0], names = <int>[];
    for (final symbol in symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    final stringOffset = textSize + symbols.length * 16;
    final trieOffset = (stringOffset + strings.length + 7) & ~7;
    final trie = ExportTrie(symbols, textOffset).encode();
    final signatureOffset = (trieOffset + trie.length + 15) & ~15;
    final signature = CodeSignature(installName, signatureOffset, textSize);
    final data = ByteData(signatureOffset + signature.size);
    final bytes = data.buffer.asUint8List();
    data.setUint32(0, 0xfeedfacf, .little);
    data.setUint32(
      4,
      object.target.architecture == .arm64 ? 0x100000c : 0x1000007,
      .little,
    );
    data.setUint32(8, object.target.architecture == .arm64 ? 0 : 3, .little);
    data.setUint32(12, 6, .little);
    data.setUint32(16, 10, .little);
    data.setUint32(20, _commandsSize, .little);
    data.setUint32(
      24,
      0x85,
      .little,
    ); // MH_NOUNDEFS | MH_DYLDLINK | MH_TWOLEVEL.
    var cursor = 32;
    int command(int kind, int size) {
      final offset = cursor;
      data.setUint32(offset, kind, .little);
      data.setUint32(offset + 4, size, .little);
      cursor += size;
      return offset;
    }

    void segment(
      String name,
      int offset,
      int fileSize,
      int protection,
      int sections,
    ) {
      final base = command(0x19, 72 + sections * 80);
      bytes.setAll(base + 8, ascii.encode(name));
      data.setUint64(base + 24, offset, .little);
      data.setUint64(base + 32, (fileSize + page - 1) & -page, .little);
      data.setUint64(base + 40, offset, .little);
      data.setUint64(base + 48, fileSize, .little);
      data.setUint32(base + 56, protection, .little);
      data.setUint32(base + 60, protection, .little);
      data.setUint32(base + 64, sections, .little);
    }

    segment('__TEXT', 0, textSize, 5, 1);
    const section = 104;
    bytes.setAll(section, ascii.encode('__text'));
    bytes.setAll(section + 16, ascii.encode('__TEXT'));
    data.setUint64(section + 32, textOffset, .little);
    data.setUint64(section + 40, object.code.length, .little);
    data.setUint32(section + 48, textOffset, .little);
    data.setUint32(section + 52, 4, .little);
    data.setUint32(section + 64, 0x80000400, .little);
    segment('__LINKEDIT', textSize, bytes.length - textSize, 1, 0);
    final id = command(0xd, _idSize);
    data.setUint32(id + 8, 24, .little);
    data.setUint32(id + 16, 0x10000, .little);
    data.setUint32(id + 20, 0x10000, .little);
    bytes.setAll(id + 24, _name);
    // dyld requires a libSystem dependency even when the library imports no symbols.
    final system = command(0xc, 56);
    data.setUint32(system + 8, 24, .little);
    data.setUint32(system + 16, 0x10000, .little);
    data.setUint32(system + 20, 0x10000, .little);
    bytes.setAll(system + 24, ascii.encode('/usr/lib/libSystem.B.dylib'));
    final build = command(0x32, 24);
    data.setUint32(build + 8, 1, .little);
    data.setUint32(build + 12, 0xb0000, .little);
    final uuid = command(0x1b, 24);
    final symtab = command(2, 24);
    data.setUint32(symtab + 8, textSize, .little);
    data.setUint32(symtab + 12, symbols.length, .little);
    data.setUint32(symtab + 16, stringOffset, .little);
    data.setUint32(symtab + 20, strings.length, .little);
    final dysymtab = command(0xb, 80);
    data.setUint32(dysymtab + 20, symbols.length, .little);
    data.setUint32(dysymtab + 24, symbols.length, .little);
    final exports = command(0x80000033, 16);
    data.setUint32(exports + 8, trieOffset, .little);
    data.setUint32(exports + 12, trie.length, .little);
    final signing = command(0x1d, 16);
    data.setUint32(signing + 8, signatureOffset, .little);
    data.setUint32(signing + 12, signature.size, .little);
    bytes.setAll(textOffset, code);
    for (final (i, symbol) in symbols.indexed) {
      final offset = textSize + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, 0xf);
      data.setUint8(offset + 5, 1);
      data.setUint64(offset + 8, textOffset + symbol.offset, .little);
    }
    bytes.setAll(stringOffset, strings);
    bytes.setAll(trieOffset, trie);
    final identifier = sha256
        .convert(Uint8List.sublistView(bytes, 0, signatureOffset))
        .bytes
        .sublist(0, 16);
    identifier[6] = (identifier[6] & 15) | 0x80;
    identifier[8] = (identifier[8] & 63) | 0x80;
    bytes.setAll(uuid + 8, identifier);
    signature.write(bytes);
    return bytes;
  }
}
