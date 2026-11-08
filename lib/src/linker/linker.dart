import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';

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
    for (final object in objects) {
      code.add(Uint8List((-code.length) & 15));
      final base = code.length;
      for (final symbol in object.symbols) {
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
    return LinkedImage(layout, module.code);
  }
}
