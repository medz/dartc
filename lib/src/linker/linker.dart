import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'input.dart';

/// Links native modules into loadable images without file IO.
abstract interface class Linker() {
  /// The explicit output platform.
  Target get target;

  /// Links an executable starting at the global code symbol [entry].
  ///
  /// [entry] includes platform decoration and selects archive members just like
  /// an unresolved reference. Linux enters with the kernel's initial stack;
  /// macOS calls it through `LC_MAIN` and uses its integer return as exit status.
  /// Linux currently requires all symbols to resolve statically. macOS supports
  /// the same dynamic dependencies as [linkSharedLibrary].
  Uint8List linkExecutable(Iterable<LinkInput> inputs, {required String entry});

  /// Resolves definitions and returns immutable bytes ready to load or write.
  ///
  /// Local symbols retain their object scope. Included objects must have unique
  /// globals, resolved imports and a matching target.
  /// Linux searches each archive's index in order at its input position, making
  /// further passes for new imports. macOS includes explicit objects first, then
  /// finds each missing symbol in the first archive that defines it, repeating
  /// for new imports. Unselected members are not decoded or included.
  /// Shared-library bindings satisfy remaining direct function calls; every
  /// declared dependency is retained. Conflicting bindings are rejected.
  /// Library availability and symbol lookup are checked by the target loader.
  Uint8List linkSharedLibrary(
    Iterable<LinkInput> inputs, {
    required String name,
  });
}
