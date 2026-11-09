import 'dart:typed_data';

import 'object_module.dart';

import 'package:dartc/target.dart';

/// Encodes relocatable objects for one explicit output platform.
abstract interface class ObjectFormat() {
  /// The selected output platform.
  Target get target;

  /// Encodes code and symbols without assigning final load addresses.
  Uint8List encodeObject(ObjectModule module);
}
