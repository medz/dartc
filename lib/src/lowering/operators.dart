import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';

/// Compares evaluated operands using Dart's null rule or the left receiver.
Value lowerEquality(
  FunctionContext context,
  ast.AstNode site,
  Value left,
  Value right, {
  bool negated = false,
}) {
  if (left.type == .nullType) {
    return context.testType(right, .nullType, negated: negated);
  }
  if (right.type == .nullType) {
    return context.testType(left, .nullType, negated: negated);
  }
  if (!left.type.hasScalarEquality) {
    unsupported(
      context.unit,
      site,
      'equality dispatch on ${left.type.dartName}',
    );
  }
  return context.current!.emit(ScalarEquals(left, right, negated: negated));
}

/// Applies [operator] after both operands have been evaluated.
Value? lowerBinary(
  FunctionContext context,
  ast.AstNode site,
  Token operator,
  Value left,
  Value? right,
) {
  if (right == null) return null;
  if (operator.type == .EQ_EQ || operator.type == .BANG_EQ) {
    return lowerEquality(
      context,
      site,
      left,
      right,
      negated: operator.type == .BANG_EQ,
    );
  }
  final member = switch (site) {
    ast.MethodReferenceExpression(:final element) => element,
    ast.RelationalPattern(:final element) => element,
    _ => null,
  };
  if (member?.library.isDartCore != true) {
    unsupported(context.unit, site, 'operator dispatch for ${operator.lexeme}');
  }
  final IntOperator op = switch (operator.type) {
    .PLUS || .PLUS_EQ || .PLUS_PLUS => .add,
    .MINUS || .MINUS_EQ || .MINUS_MINUS => .subtract,
    .STAR || .STAR_EQ => .multiply,
    .LT => .lessThan,
    .LT_EQ => .lessOrEqual,
    .GT => .greaterThan,
    .GT_EQ => .greaterOrEqual,
    _ => unsupported(context.unit, site, operator.lexeme),
  };
  if (left.type != .integer || right.type != .integer) {
    unsupported(context.unit, site, 'non-integer operator');
  }
  return context.current!.emit(IntBinary(op, left, right));
}
