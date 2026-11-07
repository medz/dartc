import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';

import 'mach_o_dylib.dart';

/// Writes Mach-O objects and dynamic libraries for macOS ARM64 and x86-64.
abstract final class MachO() {
  /// Encodes a dynamic library with [installName] and an ad-hoc code signature.
  static Uint8List shared(ObjectFile object, String installName) =>
      MachODylib.encode(object, installName);

  /// Encodes a text section and its externally visible function symbols.
  ///
  /// Symbol names are already linker names; this does not add a C prefix.
  static Uint8List encode(ObjectFile object) {
    if (object.target.operatingSystem != .macos) {
      throw ArgumentError('Mach-O output requires a macOS target.');
    }
    final strings = <int>[0], names = <int>[];
    for (final symbol in object.symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    const commandSize = 152 + 24 + 24 + 80, textOffset = 320;
    final symbolOffset = (textOffset + object.code.length + 7) & ~7;
    final stringOffset = symbolOffset + object.symbols.length * 16;
    final data = ByteData(stringOffset + strings.length);
    final bytes = data.buffer.asUint8List();
    data.setUint32(0, 0xfeedfacf, .little);
    data.setUint32(
      4,
      object.target.architecture == .arm64 ? 0x100000c : 0x1000007,
      .little,
    );
    data.setUint32(8, object.target.architecture == .arm64 ? 0 : 3, .little);
    data.setUint32(12, 1, .little);
    data.setUint32(16, 4, .little);
    data.setUint32(20, commandSize, .little);
    data.setUint32(24, 0x2000, .little);
    // LC_SEGMENT_64 owns one __TEXT,__text section.
    data.setUint32(32, 0x19, .little);
    data.setUint32(36, 152, .little);
    data.setUint64(64, object.code.length, .little);
    data.setUint64(72, textOffset, .little);
    data.setUint64(80, object.code.length, .little);
    data.setUint32(88, 7, .little);
    data.setUint32(92, 7, .little);
    data.setUint32(96, 1, .little);
    bytes.setAll(104, ascii.encode('__text'));
    bytes.setAll(120, ascii.encode('__TEXT'));
    data.setUint64(144, object.code.length, .little);
    data.setUint32(152, textOffset, .little);
    data.setUint32(156, 4, .little);
    data.setUint32(168, 0x80000400, .little);
    // LC_BUILD_VERSION identifies macOS 11 as the deployment floor.
    data.setUint32(184, 0x32, .little);
    data.setUint32(188, 24, .little);
    data.setUint32(192, 1, .little);
    data.setUint32(196, 0xb0000, .little);
    data.setUint32(208, 2, .little);
    data.setUint32(212, 24, .little);
    data.setUint32(216, symbolOffset, .little);
    data.setUint32(220, object.symbols.length, .little);
    data.setUint32(224, stringOffset, .little);
    data.setUint32(228, strings.length, .little);
    data.setUint32(232, 0xb, .little);
    data.setUint32(236, 80, .little);
    data.setUint32(252, object.symbols.length, .little);
    data.setUint32(256, object.symbols.length, .little);
    bytes.setAll(textOffset, object.code);
    bytes.setAll(stringOffset, strings);
    for (final (i, symbol) in object.symbols.indexed) {
      final offset = symbolOffset + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, 0xf);
      data.setUint8(offset + 5, 1);
      data.setUint64(offset + 8, symbol.offset, .little);
    }
    return bytes;
  }
}
