import 'signature.dart';

/// Stable semantic site identity, independent of observable source locations.
///
/// [site] is an object in the preserved source graph. [path] identifies copies
/// made by inlining or region expansion. Neither source coordinates nor facts
/// from one analyzed graph establish this identity.
final class IrOrigin(
  final FunctionTarget owner,
  final Object site, {
  Iterable<Object> path = const [],
}) {
  final List<Object> path = .unmodifiable(path);

  /// The shared semantic site before context-specific copies.
  IrOrigin get source => path.isEmpty ? this : IrOrigin(owner, site);

  /// Identifies a copy at a stable caller or region-expansion site.
  IrOrigin copiedAt(Object context) =>
      IrOrigin(owner, site, path: [...path, context]);

  @override
  bool operator ==(Object other) =>
      other is IrOrigin &&
      owner == other.owner &&
      identical(site, other.site) &&
      path.length == other.path.length &&
      path.indexed.every((entry) => entry.$2 == other.path[entry.$1]);

  @override
  int get hashCode => Object.hash(owner, site, Object.hashAll(path));
}
