/// Exports a Dart function with the explicit `dart:ffi` signature [T].
///
/// Native signatures accept `Int64`, `Double` and `Pointer<Int64>` parameters
/// and results; `Void` is also allowed as a result. Functions must be synchronous,
/// non-generic and top-level, with only required positional parameters.
///
/// {@example /test/compiler/fixtures/arithmetic.dart}
final class const Export<T>({final String? symbol});
