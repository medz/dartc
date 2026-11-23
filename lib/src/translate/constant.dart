import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'types.dart';

/// The constant variable that [element] refers to, if it is one.
VariableElement? constantVariable(Element? element) {
  final variable = switch (element) {
    GetterElement(:final variable) => variable,
    VariableElement() => element,
    _ => null,
  };
  return variable != null && variable.isConst ? variable : null;
}

/// The number that [node] is, after a minus sign if [isNegated], or null if its
/// type is something else.
Object? integerLiteral(IntegerLiteral node, {required bool isNegated}) {
  return switch (valueType(node.staticType!)) {
    .integer => node.parseIntValue(negated: isNegated),
    .float => node.parseDoubleValue(negated: isNegated),
    _ => null,
  };
}

/// The text of a constant string, or null if [node] is something else.
String? constantText(Expression node) {
  switch (node) {
    case SimpleStringLiteral(:final value):
      return value;
    case AdjacentStrings(:final strings):
      return _join(strings.map(constantText));
    case StringInterpolation(:final elements):
      return _join(elements.map(_elementText));
    case SimpleIdentifier(:final element) ||
        PrefixedIdentifier(identifier: SimpleIdentifier(:final element)):
      return constantVariable(element)?.computeConstantValue()?.toStringValue();
    default:
      return null;
  }
}

String? _elementText(InterpolationElement element) => switch (element) {
  InterpolationString(:final value) => value,
  InterpolationExpression(:final expression) => constantText(
    expression.unParenthesized,
  ),
};

String? _join(Iterable<String?> parts) =>
    parts.contains(null) ? null : parts.join();
