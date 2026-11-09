/// The scope in which a linker can resolve a definition.
enum SymbolBinding() {
  local,
  global,
}

/// The kind of definition represented by a symbol.
enum SymbolKind() {
  function,
  data,
}

/// A section-relative definition with independent link scope and visibility.
///
/// Ranges and visibility are checked when constructing its module.
final class const Symbol(
  final String name,
  final int section,
  final int offset,
  final int size, {
  final SymbolKind kind = .function,
  final SymbolBinding binding = .global,
  final bool exported = false,
});
