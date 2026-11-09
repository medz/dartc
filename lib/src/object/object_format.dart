import 'dart:typed_data';

import 'object_module.dart';

import 'package:dartc/target.dart';

/// Reads and writes relocatable objects for one explicit platform.
abstract interface class ObjectFormat() {
  /// The selected output platform.
  Target get target;

  /// Encodes sections and symbols without assigning final load addresses.
  Uint8List encodeObject(ObjectModule module);

  /// Decodes an object into immutable sections, symbols and references.
  ///
  /// Throws [FormatException] for malformed input and [UnsupportedError] for
  /// features outside the supported object format. No input bytes are retained
  /// by mutable alias. Missing symbol kind or extent remains unspecified.
  ObjectModule decodeObject(Uint8List bytes);
}
