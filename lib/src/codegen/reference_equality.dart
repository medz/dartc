import 'package:dartc/ir.dart';

/// Compares two selected references without invoking Dart equality.
final class ReferenceEquality(
  final Value left,
  final Value right, {
  final bool negated = false,
}) extends Value {
  this : super(.boolean);
}
