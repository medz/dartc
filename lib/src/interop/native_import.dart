import 'native_signature.dart';

/// A resolved native symbol and the signature used to call it.
///
/// The caller must supply the matching native implementation when linking.
/// This binding does not search libraries or resolve a Dart FFI asset ID.
final class NativeImport(final String symbol, final NativeSignature signature) {
  this {
    if (symbol.isEmpty || symbol.contains('\u0000')) {
      throw ArgumentError.value(symbol, 'symbol', 'Expected a native symbol.');
    }
  }
}
