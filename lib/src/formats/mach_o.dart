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
    if (module.imports.isNotEmpty || module.relocations.isNotEmpty) {
      throw ArgumentError('Image layout requires resolved module references.');
    }
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
    final order = List.generate(object.symbols.length, (i) => i)
      ..sort(
        (a, b) => object.symbols[a].binding.index.compareTo(
          object.symbols[b].binding.index,
        ),
      );
    final symbols = [for (final i in order) object.symbols[i]];
    final indices = {for (final (i, original) in order.indexed) original: i};
    final localCount = symbols.where((s) => s.binding == .local).length;
    final count = symbols.length + object.imports.length;
    if (count > 0x1000000) {
      throw UnsupportedError('Mach-O relocation symbol index exceeds 24 bits.');
    }
    final strings = <int>[0], names = <int>[];
    for (final name in [...symbols.map((s) => s.name), ...object.imports]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    const commandSize = 152 + 24 + 24 + 80, textOffset = 320;
    final relocationOffset = (textOffset + object.code.length + 7) & ~7;
    final symbolOffset = relocationOffset + object.relocations.length * 8;
    final stringOffset = symbolOffset + count * 16;
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
    data.setUint32(
      160,
      object.relocations.isEmpty ? 0 : relocationOffset,
      .little,
    );
    data.setUint32(164, object.relocations.length, .little);
    data.setUint32(168, 0x80000400, .little);
    // LC_BUILD_VERSION identifies macOS 11 as the deployment floor.
    data.setUint32(184, 0x32, .little);
    data.setUint32(188, 24, .little);
    data.setUint32(192, 1, .little);
    data.setUint32(196, 0xb0000, .little);
    data.setUint32(208, 2, .little);
    data.setUint32(212, 24, .little);
    data.setUint32(216, symbolOffset, .little);
    data.setUint32(220, count, .little);
    data.setUint32(224, stringOffset, .little);
    data.setUint32(228, strings.length, .little);
    data.setUint32(232, 0xb, .little);
    data.setUint32(236, 80, .little);
    data.setUint32(244, localCount, .little);
    data.setUint32(248, localCount, .little);
    data.setUint32(252, symbols.length - localCount, .little);
    data.setUint32(256, symbols.length, .little);
    data.setUint32(260, object.imports.length, .little);
    bytes.setAll(textOffset, object.code);
    bytes.setAll(stringOffset, strings);
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(
        offset + 4,
        symbol.binding == .local ? 0xe : (symbol.exported ? 0xf : 0x1f),
      );
      data.setUint8(offset + 5, 1);
      data.setUint64(offset + 8, symbol.offset, .little);
    }
    for (final (i, _) in object.imports.indexed) {
      final offset = symbolOffset + (symbols.length + i) * 16;
      data.setUint32(offset, names[symbols.length + i], .little);
      data.setUint8(offset + 4, 1);
    }
    final relocations = object.relocations.toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final (i, relocation) in relocations.indexed) {
      final index = relocation.symbol < object.symbols.length
          ? indices[relocation.symbol]!
          : symbols.length + relocation.symbol - object.symbols.length;
      data.setUint32(relocationOffset + i * 8, relocation.offset, .little);
      data.setUint32(relocationOffset + i * 8 + 4, index | 0x2d000000, .little);
    }
    return bytes;
  }
}
