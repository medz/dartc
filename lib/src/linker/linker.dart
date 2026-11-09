import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

/// Links native modules into a complete shared library without file IO.
abstract interface class Linker() {
  /// The explicit output platform.
  Target get target;

  /// Resolves definitions and returns immutable bytes ready to load or write.
  ///
  /// Local symbols retain their object scope. Duplicate globals, unresolved
  /// imports and a mismatched target are rejected before returning an image.
  Uint8List linkSharedLibrary(
    Iterable<ObjectModule> objects, {
    required String name,
  });
}
