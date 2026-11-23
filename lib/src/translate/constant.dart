import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
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

/// The `int`, `double` or `bool` that [variable] is always equal to.
Object? constantNumber(VariableElement variable) {
  final DartObject? constant = variable.computeConstantValue();
  return switch (valueType(variable.type)) {
    .integer => constant?.toIntValue(),
    .float => constant?.toDoubleValue(),
    .boolean => constant?.toBoolValue(),
    null => null,
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
