import 'package:dartc/assembler.dart';

/// An instruction reference to a module symbol, preserving local identity.
///
/// [symbol] indexes definitions followed by imports. [offset] identifies the
/// AArch64 instruction or the x86-64 displacement field within [section].
final class const Relocation(
  final int section,
  final int offset,
  final FixupEncoding encoding,
  final int symbol,
);
