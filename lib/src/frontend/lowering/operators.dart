import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';

/// Compares evaluated operands using Dart's null rule or the left receiver.
Value lowerEquality(
  FunctionContext context,
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
  return context.emit(Equals(left, right, negated: negated));
}

/// Applies [operator] after both operands have been evaluated.
Value? lowerBinary(
  FunctionContext context,
  ast.AstNode site,
  Token operator,
  Value left,
  Value? right, {
  ExtensionApplication? extension,
}) {
  if (right == null) return null;
  final direct =
      site is ast.BinaryExpression && site.leftOperand is ast.SuperExpression;
  final member = switch (site) {
    ast.MethodReferenceExpression(:final element) => element,
    ast.RelationalPattern(:final element) => element,
    _ => null,
  };
  if (operator.type == .EQ_EQ || operator.type == .BANG_EQ) {
    if (direct) {
      final negated = operator.type == .BANG_EQ;
      return context.branch(
        context.testType(right, .nullType),
        () => Constant.boolean(negated),
        () {
          final result = context.callPositionalMember(
            member,
            left,
            [context.refined(right!)],
            site,
            direct: true,
          );
          return result == null || !negated
              ? result
              : context.emit(Equals(result, const Constant.boolean(false)));
        },
        ValueType.boolean,
      );
    }
    return lowerEquality(
      context,
      left,
      right,
      negated: operator.type == .BANG_EQ,
    );
  }
  if (left.type is DynamicType && !isExtensionOwner(member?.enclosingElement)) {
    final name = switch (operator.type) {
      .PLUS_PLUS => '+',
      .MINUS_MINUS => '-',
      .PLUS_EQ ||
      .MINUS_EQ ||
      .STAR_EQ ||
      .SLASH_EQ ||
      .TILDE_SLASH_EQ ||
      .PERCENT_EQ ||
      .AMPERSAND_EQ ||
      .BAR_EQ ||
      .CARET_EQ ||
      .LT_LT_EQ ||
      .GT_GT_EQ ||
      .GT_GT_GT_EQ => operator.lexeme.substring(0, operator.lexeme.length - 1),
      _ => operator.lexeme,
    };
    return context.dynamicMember(left, .method, name, [right]);
  }
  if (member is MethodElement &&
      (isClassLike(member.enclosingElement) ||
          isExtensionOwner(member.enclosingElement)) &&
      (!member.library.isDartCore ||
          !ValueType.number.accepts(left.type) && left.type != .string)) {
    return context.callPositionalMember(
      member,
      left,
      [right],
      site,
      direct: direct,
      extension:
          extension ??
          context.extensionApplication(
            member,
            site,
            receiverType: site is ast.RelationalPattern
                ? site.matchedValueType
                : null,
          ),
    );
  }
  if (member?.library.isDartCore != true) {
    unsupported(context.unit, site, 'operator dispatch for ${operator.lexeme}');
  }
  if (member != null && member.formalParameters.isNotEmpty) {
    right = context.convert(
      right,
      context.typeOf(member.formalParameters.first.type, site),
    );
  }
  if (left.type == .string &&
      right.type == .string &&
      (operator.type == .PLUS || operator.type == .PLUS_EQ)) {
    return context.emit(StringConcat(left, right));
  }
  final IntOperator op = switch (operator.type) {
    .PLUS || .PLUS_EQ || .PLUS_PLUS => .add,
    .MINUS || .MINUS_EQ || .MINUS_MINUS => .subtract,
    .STAR || .STAR_EQ => .multiply,
    .SLASH || .SLASH_EQ => .divide,
    .TILDE_SLASH || .TILDE_SLASH_EQ => .truncateDivide,
    .PERCENT || .PERCENT_EQ => .modulo,
    .AMPERSAND || .AMPERSAND_EQ => .bitAnd,
    .BAR || .BAR_EQ => .bitOr,
    .CARET || .CARET_EQ => .bitXor,
    .LT_LT || .LT_LT_EQ => .shiftLeft,
    .GT_GT || .GT_GT_EQ => .shiftRight,
    .GT_GT_GT || .GT_GT_GT_EQ => .unsignedShiftRight,
    .LT => .lessThan,
    .LT_EQ => .lessOrEqual,
    .GT => .greaterThan,
    .GT_EQ => .greaterOrEqual,
    _ => unsupported(context.unit, site, operator.lexeme),
  };
  if ((op == .truncateDivide || op == .modulo) &&
      left.type != .floating &&
      right.type != .floating) {
    context.bindings.requireSdkClass(
      member!.library.getClass('IntegerDivisionByZeroException')!,
    );
  }
  if (left.type == .integer && right.type == .integer) {
    if (op == .shiftLeft || op == .shiftRight || op == .unsignedShiftRight) {
      context.bindings.requireSdkClass(
        member!.library.getClass('ArgumentError')!,
      );
    }
    return context.emit(IntBinary(op, left, right));
  }
  if (!ValueType.number.accepts(left.type) ||
      !ValueType.number.accepts(right.type)) {
    unsupported(context.unit, site, 'non-numeric operator');
  }
  final numeric = switch (op) {
    .add => NumericOperator.add,
    .subtract => NumericOperator.subtract,
    .multiply => NumericOperator.multiply,
    .divide => NumericOperator.divide,
    .truncateDivide => NumericOperator.truncateDivide,
    .modulo => NumericOperator.modulo,
    .lessThan => NumericOperator.lessThan,
    .lessOrEqual => NumericOperator.lessOrEqual,
    .greaterThan => NumericOperator.greaterThan,
    .greaterOrEqual => NumericOperator.greaterOrEqual,
    _ => unsupported(context.unit, site, 'non-integer bitwise operator'),
  };
  if (numeric == .truncateDivide) {
    context.bindings.requireSdkClass(
      member!.library.getClass('UnsupportedError')!,
    );
  }
  return context.emit(NumericBinary(numeric, left, right));
}
