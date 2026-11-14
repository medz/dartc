import 'native_signature.dart';

/// A resolved native symbol and the signature used to call it.
///
/// The caller must supply the matching native implementation when linking.
/// This binding does not search libraries or resolve a Dart FFI asset ID.
final class NativeImport(
  /// The native symbol name before platform decoration.
  final String symbol,
  final NativeSignature signature, {

  /// Whether the binding promises a short, nonblocking call without callbacks.
  final bool isLeaf = false,

  /// An explicit promise that the native implementation neither allocates Dart
  /// objects, throws Dart exceptions, nor reenters Dart, including indirectly.
  /// This is independent of the scheduling promise made by [isLeaf].
  final bool isNonAllocating = false,
}) {
  this {
    if (symbol.isEmpty || symbol.contains('\u0000')) {
      throw ArgumentError.value(symbol, 'symbol', 'Expected a native symbol.');
    }
  }
}
