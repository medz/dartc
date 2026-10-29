/// Exposes a Dart declaration through a native library's C ABI.
///
/// [T] is an explicit `dart:ffi` function signature or native data type.
/// [symbol] defaults to the annotated declaration's name.
class Export<T> {
  final String? symbol;

  const Export({this.symbol});
}
