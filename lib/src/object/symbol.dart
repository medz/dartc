/// The scope in which a linker can resolve a definition.
enum SymbolBinding() {
  local,
  global,
}

/// A function definition with independent link scope and export visibility.
///
/// Ranges and visibility are checked when constructing its module.
final class const Symbol(
  final String name,
  final int offset,
  final int size, {
  final SymbolBinding binding = .global,
  final bool exported = false,
});
