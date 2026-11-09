/// Exports a Dart function with the explicit `dart:ffi` signature [T].
///
/// Native signatures accept fixed-width integers, `Double` and pointers to
/// native integers; `Void` is also allowed as a result. Functions must be
/// synchronous, non-generic and top-level, with required positional parameters.
///
/// {@example /test/compiler/fixtures/arithmetic.dart}
final class const Export<T>({final String? symbol});
