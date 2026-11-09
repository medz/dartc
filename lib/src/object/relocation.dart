import 'package:dartc/assembler.dart';

/// A reference to a module symbol, preserving local identity.
///
/// [symbol] indexes definitions followed by imports. [offset] locates the
/// field to patch within [section].
sealed class const Relocation(
  final int section,
  final int offset,
  final int symbol,
) {
  /// References a symbol from an instruction's address or displacement field.
  const factory instruction(
    int section,
    int offset,
    FixupEncoding encoding,
    int symbol, {
    bool indirect,
  }) = InstructionRelocation;

  /// Stores a symbol's address in an aligned, zero-filled 64-bit data field.
  const factory address(int section, int offset, int symbol) =
      AddressRelocation;
}

/// An instruction reference with its assembler-owned encoding.
final class const InstructionRelocation(
  super.section,
  super.offset,
  final FixupEncoding encoding,
  super.symbol, {

  /// Whether the instruction addresses a pointer slot for [symbol].
  ///
  /// The slot holds the symbol's address after loading. Supported instructions
  /// are AArch64 ADRP/LDR and x86-64 RIP-relative MOV, with no symbol addend.
  final bool indirect = false,
}) extends Relocation;

/// An absolute address in initialized data, with no symbol addend.
///
/// The source section must have at least eight-byte alignment. Loading a
/// shared library or position-independent executable adjusts this address.
final class const AddressRelocation(super.section, super.offset, super.symbol)
    extends Relocation;
