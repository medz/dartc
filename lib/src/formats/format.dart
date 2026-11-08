import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';

/// Encodes relocatable objects for one explicit output platform.
abstract interface class ObjectFormat() {
  /// The selected output platform.
  Target get target;

  /// Encodes code and symbols without assigning final load addresses.
  Uint8List encodeObject(ObjectModule module);
}

/// Encodes native objects and lays out their shared-library images.
abstract interface class ImageFormat() implements ObjectFormat {
  /// Determines code placement for a shared library before address fixups.
  ///
  /// The returned layout retains [module] without replacing its contents.
  ImageLayout layoutImage(ObjectModule module, {required String libraryName});

  /// Encodes the patched code using the layout that produced its addresses.
  Uint8List encodeImage(LinkedImage image);
}
