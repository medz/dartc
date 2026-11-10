import 'package:dartc/ir.dart';

/// The unchanged IEEE 754 bits of a selected double value.
final class DoubleBits(final Value operand) extends Value {
  this : super(.integer) {
    if (operand.type != .floating) throw ArgumentError('Expected a double.');
  }
}
