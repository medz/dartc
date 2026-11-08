import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/arm64.dart';
import 'package:dartc/x64.dart';

/// Resolves native modules using the placement chosen by an image format.
final class Linker(final ImageFormat format) {
  /// Builds an in-memory shared image without changing files.
  LinkedImage link(
    Iterable<ObjectModule> input, {
    required String libraryName,
  }) {
    final objects = input.toList();
    if (objects.isEmpty || objects.any((o) => o.target != format.target)) {
      throw ArgumentError('Expected non-empty modules for the format target.');
    }
    final code = BytesBuilder(copy: false), symbols = <Symbol>[];
    final bases = <int>[], globals = <String, int>{};
    for (final object in objects) {
      code.add(Uint8List((-code.length) & 15));
      final base = code.length;
      bases.add(base);
      for (final symbol in object.symbols) {
        if (symbol.binding == .global) {
          if (globals.containsKey(symbol.name)) {
            throw ArgumentError('Duplicate global: ${symbol.name}');
          }
          globals[symbol.name] = base + symbol.offset;
        }
        symbols.add(
          .new(
            symbol.name,
            base + symbol.offset,
            symbol.size,
            binding: symbol.binding,
            exported: symbol.exported,
          ),
        );
      }
      code.add(object.code);
    }
    final module = ObjectModule(format.target, code.takeBytes(), symbols);
    final layout = format.layoutImage(module, libraryName: libraryName);
    assert(identical(layout.module, module));
    final patched = Uint8List.fromList(module.code);
    final data = ByteData.sublistView(patched);
    for (final (i, object) in objects.indexed) {
      for (final name in object.imports) {
        if (!globals.containsKey(name)) {
          throw ArgumentError('Undefined symbol: $name');
        }
      }
      for (final reference in object.relocations) {
        final destination = reference.symbol < object.symbols.length
            ? bases[i] + object.symbols[reference.symbol].offset
            : globals[object.imports[reference.symbol -
                  object.symbols.length]]!;
        final offset = bases[i] + reference.offset;
        final sourceAddress = layout.codeAddress + offset;
        final targetAddress = layout.codeAddress + destination;
        switch (reference.kind) {
          case .arm64Call26:
            data.patchArm64Call(offset, targetAddress - sourceAddress);
          case .x64Call32:
            data.patchX64Call(offset, targetAddress - (sourceAddress + 4));
        }
      }
    }
    return LinkedImage(layout, patched);
  }
}
