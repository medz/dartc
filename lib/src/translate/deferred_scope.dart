import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';

/// What translating one function needs to know of the libraries that the
/// program loads itself.
abstract interface class DeferredScope() {
  /// The object for [prefix], which tells whether its library is loaded.
  HirValue prefix(FunctionBuilder builder, PrefixElement prefix);

  /// Loads the library of [prefix]. Gives a future.
  HirValue load(FunctionBuilder builder, PrefixElement prefix);

  /// The function `loadLibrary` of [prefix], which is [element], as a value.
  HirValue loader(
    FunctionBuilder builder,
    PrefixElement prefix,
    ExecutableElement element,
  );
}
