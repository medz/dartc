import 'dart:typed_data';

/// LIR that this version cannot translate yet.
final class EmitUnsupported(final String function, final String what)
    implements Exception {
  @override
  String toString() => 'EmitUnsupported: $function: $what';
}

/// How a symbol's address enters an ARM64 instruction.
enum RelocationKind() {
  /// A 26-bit word displacement in `bl`.
  call26,

  /// A page displacement in `adrp`.
  page21,

  /// The low 12 address bits in `add`.
  pageOffset12,
}

/// An instruction at [offset] awaiting the address of [symbol].
final class Relocation(
  final int offset,
  final RelocationKind kind,
  final String symbol,
);

/// Position-independent code before its final addresses are known.
final class EmittedCode(
  final Uint8List text,

  /// The offset of each function in [text].
  Map<String, int> functions,
  Iterable<Relocation> relocations, {

  /// Functions the system supplies, by their C names.
  Iterable<String> externals = const [],
}) {
  final List<String> externals = .unmodifiable(externals);
  final Map<String, int> functions = .unmodifiable(functions);
  final List<Relocation> relocations = .unmodifiable(relocations);
}
