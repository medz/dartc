import 'native_signature.dart';

/// A native function or data declaration awaiting asset and symbol resolution.
final class const NativeReference(
  /// The exact asset ID after applying the library's default.
  final String assetId,

  /// The symbol requested within that asset.
  final String symbol,

  /// A function signature or the native type of the referenced storage.
  final NativeTypeRef type, {

  /// Whether the declaration promises a short, nonblocking call without callbacks.
  final bool isLeaf = false,
});
