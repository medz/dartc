/// Exports a Dart function with the explicit `dart:ffi` signature [T].
///
/// The initial native backend accepts `Int64` arguments and results on
/// synchronous, non-generic top-level functions. Other signatures are diagnosed.
///
/// {@example /test/compiler/fixtures/arithmetic.dart}
final class const Export<T>({final String? symbol});
