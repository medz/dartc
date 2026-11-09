import 'native_signature.dart';

/// A native function declaration whose asset and symbol still need resolution.
final class const NativeReference(
  /// The exact asset ID after applying the library's default.
  final String assetId,

  /// The symbol requested within that asset.
  final String symbol,

  /// The native parameter and result types.
  final NativeSignature signature, {

  /// Whether the declaration promises a short, nonblocking call without callbacks.
  final bool isLeaf = false,
});
