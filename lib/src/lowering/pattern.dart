import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'operators.dart';

/// Matches [subject] and returns the declarations visible on the successful path.
Iterable<PatternVariableElement> matchGuarded(
  FunctionContext context,
  ast.GuardedPattern guarded,
  Value subject,
  JumpTarget failure,
  Value? Function(ast.Expression) evaluate,
) {
  final bindings = <PatternVariableElement, Value>{};
  final matcher = _Matcher(context);
  matcher.match(guarded.pattern, subject, failure, bindings);
  if (context.current == null) return const [];
  for (final MapEntry(:key, :value) in bindings.entries) {
    context.declare(
      key,
      valueType(key.type, context.unit, guarded.pattern),
      value,
    );
  }
  if (guarded.whenClause case final clause?) {
    context.guard(evaluate(clause.expression), failure);
  }
  return bindings.keys;
}

final class _Matcher(final FunctionContext context) {
  void match(
    ast.DartPattern pattern,
    Value input,
    JumpTarget failure,
    Map<PatternVariableElement, Value> bindings,
  ) {
    if (context.current == null) return;
    final value = context.refined(input);
    switch (pattern) {
      case ast.ParenthesizedPattern(:final pattern):
        match(pattern, value, failure, bindings);
      case ast.WildcardPattern(:final type):
        if (type != null) {
          context.guard(
            context.testType(value, valueType(type.type!, context.unit, type)),
            failure,
          );
        }
      case ast.DeclaredVariablePattern():
        final variable = pattern.declaredFragment!.element;
        final type = valueType(variable.type, context.unit, pattern);
        context.guard(context.testType(value, type), failure);
        if (context.current != null) {
          bindings[variable] = context.cast(value, type);
        }
      case ast.ConstantPattern(:final expression):
        final constant = scalarValue(
          expression.computeConstantValue()?.value,
          context.unit,
          pattern,
        );
        context.guard(
          lowerEquality(context, pattern, constant, value),
          failure,
        );
      case ast.RelationalPattern(:final operand, :final operator):
        final constant = scalarValue(
          operand.computeConstantValue()?.value,
          context.unit,
          operand,
        );
        context.guard(
          lowerBinary(context, pattern, operator, value, constant),
          failure,
        );
      case ast.CastPattern(:final pattern, :final type):
        final cast = context.normal(
          context.cast(value, valueType(type.type!, context.unit, type)),
        );
        if (cast != null) match(pattern, cast, failure, bindings);
      case ast.NullAssertPattern(:final pattern):
        final checked = context.normal(context.checkNotNull(value));
        if (checked != null) match(pattern, checked, failure, bindings);
      case ast.NullCheckPattern(:final pattern):
        context.guard(
          context.testType(value, .nullType, negated: true),
          failure,
        );
        match(pattern, value, failure, bindings);
      case ast.LogicalAndPattern(:final leftOperand, :final rightOperand):
        match(leftOperand, value, failure, bindings);
        match(rightOperand, value, failure, bindings);
      case ast.LogicalOrPattern():
        _or(pattern, value, failure, bindings);
      default:
        unsupported(
          context.unit,
          pattern,
          'pattern starting with ${pattern.beginToken.lexeme}',
        );
    }
  }

  void _or(
    ast.LogicalOrPattern pattern,
    Value value,
    JumpTarget failure,
    Map<PatternVariableElement, Value> bindings,
  ) {
    Map<PatternVariableElement, Value> arm(
      ast.DartPattern operand,
      JumpTarget reject,
    ) {
      final values = <PatternVariableElement, Value>{};
      match(operand, value, reject, values);
      return {
        for (final MapEntry(:key, :value) in values.entries)
          key.join ?? key: value,
      };
    }

    final next = JumpTarget(context);
    final left = arm(pattern.leftOperand, next);
    if (!next.hasIncoming) {
      bindings.addAll(left);
      return;
    }
    if (context.current == null) {
      next.enter();
      bindings.addAll(arm(pattern.rightOperand, failure));
      return;
    }
    final done = next.sibling([
      for (final variable in left.keys)
        valueType(variable.type, context.unit, pattern),
    ]);
    done.jump(left.values.toList());
    next.enter();
    final right = arm(pattern.rightOperand, failure);
    if (context.current != null) {
      done.jump([for (final variable in left.keys) right[variable]!]);
    }
    final joined = done.enter()!;
    for (final (i, variable) in left.keys.indexed) {
      bindings[variable] = joined.parameters[i];
    }
  }
}
