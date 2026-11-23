import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'operators.dart';
import 'places.dart';
import 'scope.dart';
import 'types.dart';

/// Translates assignments of every kind.
final class AssignmentTranslator(
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final PlaceTranslator _places,
  final OperatorTranslator _operators,
  final Conversions _conversions,
) {
  /// Adds or subtracts 1, giving the value before or after.
  HirValue step(
    CompoundAssignmentExpression node,
    Expression operand,
    String operator, {
    required bool after,
  }) {
    final place = _places.place(node, operand);
    final old = _read(place, node);
    final one = _builder.add(HirConst(1));
    final stepped = _operators.binary(
      node,
      operator[0],
      (old, node.readType!),
      (one, _conversions.types.intType),
    );
    _places.write(place, stepped);
    return after ? stepped : old;
  }

  /// What [node] reads of [place] before it assigns that.
  HirValue _read(Place place, CompoundAssignmentExpression node) {
    final value = _places.read(place), type = valueType(node.readType!);
    return type == null ? value : _conversions.coerce(value, type);
  }

  HirValue assign(AssignmentExpression node) {
    final place = _places.place(node, node.leftHandSide);
    final operator = node.operator.lexeme;
    if (operator == '=') {
      return _write(place, node.rightHandSide);
    }
    final old = _read(place, node);
    if (operator == '??=') {
      final type = valueType(node.staticType!)!;
      return _conversions.ifNull(node, type, old, () {
        final result = _write(place, node.rightHandSide);
        return _conversions.coerce(result, type);
      });
    }
    final readType = node.readType!;
    final (right, rightType) = _operators.operand(
      node.rightHandSide,
      old,
      node.element,
      readType,
    );
    final result = _operators.binary(
      node,
      operator.substring(0, operator.length - 1),
      (old, readType),
      (right, rightType),
    );
    _places.write(place, result);
    return result;
  }

  /// Assigns [node], whose own value is the result.
  HirValue _write(Place place, Expression node) {
    final type = node.staticType!;
    final result = _evaluator.value(node, placeholder: valueType(place.type)!);
    if (type is! DynamicType) {
      _places.write(place, result);
      return result;
    }
    final checked =
        _conversions.cast(result, type, place.type) ??
        (throw _builder.unit.unsupported(node, 'testing for ${place.type}'));
    _places.write(place, checked);
    return checked;
  }
}
