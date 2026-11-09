import 'package:dartc/assembler.dart';

/// An instruction reference to a module symbol, preserving local identity.
///
/// [symbol] indexes definitions followed by imports. [offset] identifies the
/// AArch64 instruction or the x86-64 displacement field within [section].
final class const Relocation(
  final int section,
  final int offset,
  final FixupEncoding encoding,
  final int symbol, {

  /// Whether the instruction addresses a pointer slot for [symbol].
  ///
  /// The slot holds the symbol's address after loading. Supported instructions
  /// are AArch64 ADRP/LDR and x86-64 RIP-relative MOV, with no symbol addend.
  final bool indirect = false,
});
