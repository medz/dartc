import 'package:dartc/assembler.dart';

/// A call to a module symbol, with no implicit name lookup for local definitions.
///
/// [symbol] indexes definitions followed by imports. [offset] identifies the
/// AArch64 instruction or the x86-64 displacement field, relative to code start.
final class const Relocation(
  final int offset,
  final FixupEncoding encoding,
  final int symbol,
);
