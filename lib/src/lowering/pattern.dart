import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';
import 'function_context.dart';
import 'operators.dart';
import 'record.dart';

/// Matches [subject] and returns the declarations visible on the successful path.
Iterable<PatternVariableElement> matchGuarded(
  FunctionContext context,
  ast.GuardedPattern guarded,
  Value subject,
  JumpTarget failure,
  Value? Function(ast.Expression) evaluate,
) {
  final bindings = declarePattern(context, guarded.pattern, subject, failure);
  if (context.current == null) return const [];
  if (guarded.whenClause case final clause?) {
    context.guard(evaluate(clause.expression), failure);
  }
  return bindings;
}

/// Destructures [subject] before introducing any local declarations.
Iterable<PatternVariableElement> declarePattern(
  FunctionContext context,
  ast.DartPattern pattern,
  Value? subject, [
  JumpTarget? failure,
]) {
  if (subject == null) return const [];
  final bindings = <PatternVariableElement, Value>{};
  _Matcher(context).match(pattern, subject, failure, bindings);
  if (context.current == null) return const [];
  for (final MapEntry(:key, :value) in bindings.entries) {
    context.declare(key, valueType(key.type, context.unit, pattern), value);
  }
  return bindings.keys;
}

/// Commits local writes together after every field has matched, then returns [subject].
Value? assignPattern(
  FunctionContext context,
  ast.DartPattern pattern,
  Value? subject,
) {
  if (subject == null) return null;
  final writes = <VariableElement, Value>{};
  _Matcher(context).match(pattern, subject, null, writes);
  if (context.current == null) return null;
  context.locals.addAll(writes);
  return subject;
}

final class _Matcher(final FunctionContext context) {
  Value? _require(Value value, ValueType type, JumpTarget? failure) {
    if (type.accepts(value.type)) return context.normal(value);
    if (failure != null) {
      context.guard(context.testType(value, type), failure);
      if (context.current == null) return null;
    }
    return context.normal(context.cast(value, type));
  }

  void match(
    ast.DartPattern pattern,
    Value input,
    JumpTarget? failure,
    Map<VariableElement, Value> bindings,
  ) {
    if (context.current == null) return;
    final value = context.refined(input);
    switch (pattern) {
      case ast.ParenthesizedPattern(:final pattern):
        match(pattern, value, failure, bindings);
      case ast.WildcardPattern(:final type):
        if (type != null) {
          _require(value, valueType(type.type!, context.unit, type), failure);
        }
      case ast.DeclaredVariablePattern():
        final variable = pattern.declaredFragment!.element;
        final bound = _require(
          value,
          valueType(variable.type, context.unit, pattern),
          failure,
        );
        if (bound != null) bindings[variable] = bound;
      case ast.AssignedVariablePattern(element: final VariableElement variable)
          when context.locals.containsKey(variable):
        final bound = _require(
          value,
          valueType(variable.type, context.unit, pattern),
          null,
        );
        if (bound != null) bindings[variable] = bound;
      case ast.RecordPattern(:final fields):
        final any = ValueType.object.nullable;
        final required = RecordType(
          [
            for (final field in fields)
              if (field.name == null) any,
          ],
          {
            for (final field in fields)
              if (field.name != null) field.effectiveName!: any,
          },
        );
        final record = _require(value, required, failure);
        if (record == null) return;
        var positional = 0;
        for (final field in fields) {
          final slot = field.name == null
              ? positional++
              : required.slots[field.effectiveName!]!;
          if (field.pattern.unParenthesized case ast.WildcardPattern(
            type: null,
          )) {
            continue;
          }
          final item = context.normal(readRecordField(context, record, slot));
          if (item == null) return;
          match(field.pattern, item, failure, bindings);
          if (context.current == null) return;
        }
      case ast.ConstantPattern(:final expression):
        final constant = constantValue(
          expression.computeConstantValue()?.value,
          context.unit,
          pattern,
        );
        context.guard(lowerEquality(context, constant, value), failure!);
      case ast.RelationalPattern(:final operand, :final operator):
        final constant = constantValue(
          operand.computeConstantValue()?.value,
          context.unit,
          operand,
        );
        context.guard(
          lowerBinary(context, pattern, operator, value, constant),
          failure!,
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
          failure!,
        );
        match(pattern, value, failure, bindings);
      case ast.LogicalAndPattern(:final leftOperand, :final rightOperand):
        match(leftOperand, value, failure, bindings);
        match(rightOperand, value, failure, bindings);
      case ast.LogicalOrPattern():
        _or(pattern, value, failure!, bindings);
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
    Map<VariableElement, Value> bindings,
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
