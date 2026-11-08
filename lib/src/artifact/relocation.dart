/// The instruction field patched when resolving a direct call.
enum RelocationKind() {
  arm64Call26,
  x64Call32,
}

/// A call to a module symbol, with no implicit name lookup for local definitions.
///
/// [symbol] indexes definitions followed by imports. [offset] identifies the
/// AArch64 instruction or the x86-64 displacement field, relative to code start.
final class const Relocation(
  final int offset,
  final RelocationKind kind,
  final int symbol,
);
