/// The scope in which a linker can resolve a definition.
enum SymbolBinding() {
  local,
  global,
}

/// The kind of definition represented by a symbol.
enum SymbolKind() {
  /// The input format does not describe the definition's kind.
  unknown,
  function,
  data,
}

/// A section-relative definition with independent link scope and visibility.
///
/// Symbols may alias or overlap; sections own the underlying storage.
/// Ranges and visibility are checked when constructing the containing module.
final class const Symbol(
  final String name,
  final int section,
  final int offset,

  /// The known positive extent, or `null` when the input has no size.
  final int? size, {
  final SymbolKind kind = .function,
  final SymbolBinding binding = .global,
  final bool exported = false,
});
