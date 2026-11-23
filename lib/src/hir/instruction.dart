/// A Dart value computed once, in order, inside a block.
///
/// Every value is currently an `int`.
sealed class HirInstruction() {
  /// The operands, in evaluation order.
  List<HirInstruction> get inputs;
}

/// An `int` literal.
final class HirInt(final int value) extends HirInstruction {
  @override
  List<HirInstruction> get inputs => const [];
}

/// The `int` operators that always succeed.
enum HirIntOperator(final String symbol) {
  add('+'),
  subtract('-'),
  multiply('*'),
  and('&'),
  or('|'),
  xor('^'),
}

final class HirIntBinary(
  final HirIntOperator operator,
  final HirInstruction left,
  final HirInstruction right,
) extends HirInstruction {
  @override
  List<HirInstruction> get inputs => [left, right];
}

enum HirIntPrefix(final String symbol) {
  negate('-'),
  complement('~'),
}

final class HirIntUnary(
  final HirIntPrefix operator,
  final HirInstruction operand,
) extends HirInstruction {
  @override
  List<HirInstruction> get inputs => [operand];
}

/// The operation ending a block.
sealed class HirTerminator() {
  List<HirInstruction> get inputs;
}

/// Returns from the function without a value.
final class HirReturn() extends HirTerminator {
  @override
  List<HirInstruction> get inputs => const [];
}

/// Ends the process, as `exit` from `dart:io` does.
final class HirExit(final HirInstruction code) extends HirTerminator {
  @override
  List<HirInstruction> get inputs => [code];
}
