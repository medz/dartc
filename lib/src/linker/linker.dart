import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'input.dart';

/// Links native modules into a complete shared library without file IO.
abstract interface class Linker() {
  /// The explicit output platform.
  Target get target;

  /// Resolves definitions and returns immutable bytes ready to load or write.
  ///
  /// Local symbols retain their object scope. Included objects must have unique
  /// globals, resolved imports and a matching target.
  /// Linux searches each archive's index in order at its input position, making
  /// further passes for new imports. macOS includes explicit objects first, then
  /// finds each missing symbol in the first archive that defines it, repeating
  /// for new imports. Unselected members are not decoded or included.
  Uint8List linkSharedLibrary(
    Iterable<LinkInput> inputs, {
    required String name,
  });
}
