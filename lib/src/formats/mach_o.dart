import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';

import 'format.dart';

import 'mach_o_dylib.dart';

/// Writes Mach-O objects and dynamic libraries for macOS ARM64 and x86-64.
final class MachO(@override final Target target) implements ImageFormat {
  this {
    if (target.operatingSystem != .macos) {
      throw ArgumentError('Mach-O requires a macOS target.');
    }
  }

  @override
  ImageLayout layoutImage(ObjectModule module, {required String libraryName}) {
    _checkTarget(module);
    if (libraryName.isEmpty || libraryName.contains('\u0000')) {
      throw ArgumentError.value(libraryName, 'libraryName');
    }
    return MachODylibLayout(module, '@rpath/$libraryName');
  }

  @override
  Uint8List encodeImage(LinkedImage image) {
    final layout = image.layout;
    if (layout is! MachODylibLayout) {
      throw ArgumentError('Expected a Mach-O layout.');
    }
    _checkTarget(layout.module);
    return layout.encode(image.code);
  }

  void _checkTarget(ObjectModule module) {
    if (module.target != target) throw ArgumentError('Mach-O target mismatch.');
  }

  @override
  Uint8List encodeObject(ObjectModule object) {
    _checkTarget(object);
    final symbols = [...object.symbols]
      ..sort((a, b) => a.binding.index.compareTo(b.binding.index));
    final localCount = symbols.where((s) => s.binding == .local).length;
    final strings = <int>[0], names = <int>[];
    for (final symbol in symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    const commandSize = 152 + 24 + 24 + 80, textOffset = 320;
    final symbolOffset = (textOffset + object.code.length + 7) & ~7;
    final stringOffset = symbolOffset + symbols.length * 16;
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
    data.setUint32(220, symbols.length, .little);
    data.setUint32(224, stringOffset, .little);
    data.setUint32(228, strings.length, .little);
    data.setUint32(232, 0xb, .little);
    data.setUint32(236, 80, .little);
    data.setUint32(244, localCount, .little);
    data.setUint32(248, localCount, .little);
    data.setUint32(252, symbols.length - localCount, .little);
    data.setUint32(256, symbols.length, .little);
    bytes.setAll(textOffset, object.code);
    bytes.setAll(stringOffset, strings);
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, symbol.binding == .local ? 0xe : 0xf);
      data.setUint8(offset + 5, 1);
      data.setUint64(offset + 8, symbol.offset, .little);
    }
    return bytes;
  }
}
