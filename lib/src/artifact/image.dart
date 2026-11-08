import 'dart:typed_data';

import 'object_module.dart';

/// The code placement chosen by a native file format before linking addresses.
abstract interface class ImageLayout() {
  /// The merged module whose definitions use section-relative offsets.
  ObjectModule get module;

  /// The byte offset of the code section in the output file.
  int get codeOffset;

  /// The virtual address of the code section relative to the image base.
  int get codeAddress;
}

/// Patched machine code and the layout used to determine its addresses.
final class LinkedImage(final ImageLayout layout, List<int> code) {
  /// An immutable copy of the patched code.
  final Uint8List code = Uint8List.fromList(code).asUnmodifiableView();

  this {
    if (layout.codeOffset < 0 ||
        layout.codeAddress < 0 ||
        code.length != layout.module.code.length ||
        code.any((byte) => byte < 0 || byte > 255) ||
        layout.module.target.architecture == .arm64 &&
            (layout.codeOffset % 4 != 0 || layout.codeAddress % 4 != 0)) {
      throw ArgumentError('Invalid linked code or image placement.');
    }
  }
}
