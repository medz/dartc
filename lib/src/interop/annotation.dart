/// Exports a Dart function to C with the `dart:ffi` type [T].
///
/// [T] is a function type made of native types, as those of `dart:ffi` are
/// given elsewhere. Exported functions are synchronous, of a library and not
/// generic, and have required positional parameters only. They are called
/// [symbol] in C, or else as in Dart.
///
/// ```dart
/// @Export<Int64 Function(Int64, Int64)>(symbol: 'math_add')
/// int add(int a, int b) => a + b;
/// ```
final class const Export<T>({final String? symbol});
