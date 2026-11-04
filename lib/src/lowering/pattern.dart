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
  Value? Function(ast.Expression) evaluate, [
  PatternCache? cache,
]) {
  final bindings = declarePattern(
    context,
    guarded.pattern,
    subject,
    failure,
    cache,
  );
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
  PatternCache? cache,
]) {
  if (subject == null) return const [];
  final bindings = <PatternVariableElement, Value>{};
  _Matcher(
    context,
    cache ?? PatternCache(context, [pattern]),
  ).match(pattern, subject, failure, bindings);
  if (context.current == null) return const [];
  for (final MapEntry(:key, :value) in bindings.entries) {
    context.declare(key, context.typeOf(key.type, pattern), value);
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
  _Matcher(
    context,
    PatternCache(context, [pattern]),
  ).match(pattern, subject, null, writes);
  if (context.current == null) return null;
  for (final MapEntry(:key, :value) in writes.entries) {
    context.writeLocal(key, value);
  }
  return subject;
}

/// Shares field extractions and comparison results across one pattern match.
final class PatternCache {
  final FunctionContext context;
  final _cells = <Object, (Value, Value)>{};

  // Collect all alternatives before emitting their lazy cache storage.
  // ignore: use_primary_constructors
  new(this.context, Iterable<ast.DartPattern> patterns) {
    final counts = <Object, int>{};
    void collect(ast.DartPattern pattern, String path) {
      switch (pattern) {
        case ast.RelationalPattern(:final operand, :final operator):
          final key = comparisonKey(path, operator.lexeme, operand);
          counts.update(key, (count) => count + 1, ifAbsent: () => 1);
        case ast.ConstantPattern(:final expression):
          final key = comparisonKey(path, 'constant==', expression);
          counts.update(key, (count) => count + 1, ifAbsent: () => 1);
        case ast.ObjectPattern(:final fields):
          for (final field in fields) {
            final key = _fieldPath(path, field);
            counts.update(key, (count) => count + 1, ifAbsent: () => 1);
            collect(field.pattern, key);
          }
        case ast.RecordPattern(:final fields):
          var index = 0;
          for (final field in fields) {
            final key =
                '$path/${field.name == null ? '\$${++index}' : field.effectiveName}';
            collect(field.pattern, key);
          }
        case ast.LogicalAndPattern(:final leftOperand, :final rightOperand) ||
            ast.LogicalOrPattern(:final leftOperand, :final rightOperand):
          collect(leftOperand, path);
          collect(rightOperand, path);
        case ast.ParenthesizedPattern(:final pattern) ||
            ast.CastPattern(:final pattern) ||
            ast.NullAssertPattern(:final pattern) ||
            ast.NullCheckPattern(:final pattern):
          collect(pattern, path);
        default:
          break;
      }
    }

    for (final pattern in patterns) {
      collect(pattern, '');
    }
    for (final MapEntry(:key, :value) in counts.entries) {
      if (value < 2) continue;
      _cells[key] = (
        context.emit(
          NewCell(CellType(ValueType.boolean), Constant.boolean(false)),
        ),
        context.emit(
          NewCell(
            CellType(ValueType.object.nullable),
            const Constant.nullValue(),
          ),
        ),
      );
    }
  }

  Object comparisonKey(String path, String operator, ast.Expression operand) =>
      (
        path,
        operator == '!=' ? '==' : operator,
        _constantKey(
          context.bindings.constantValue(
            operand.computeConstantValue()?.value,
            context.unit,
            operand,
          ),
        ),
      );

  Value? read(Object key, Value? Function() extract) {
    final cells = _cells[key];
    if (cells == null) return extract();
    final (ready, stored) = cells;
    return context.branch(
      context.current!.emit(ReadCell(ready)),
      () => context.current!.emit(ReadCell(stored)),
      () {
        final value = extract();
        if (value == null) return null;
        context.current!.emit(WriteCell(stored, value));
        context.current!.emit(WriteCell(ready, Constant.boolean(true)));
        return value;
      },
      ValueType.object.nullable,
    );
  }
}

Object _constantKey(Constant value) => switch (value) {
  ScalarConstant(:final type, :final value) => (
    type,
    value is double ? value.toString() : value,
  ),
  FunctionConstant(
    :final target,
    :final ownerType,
    :final typeArguments,
    :final constructorSignature,
    :final constructorAlias,
  ) =>
    (
      target,
      ownerType,
      constructorSignature,
      constructorAlias,
      typeArguments?.fold<Object?>(null, (tail, type) => (tail, type)),
    ),
  RecordConstant(:final type, :final fields) => (
    type,
    fields.fold<Object?>(null, (tail, field) => (tail, _constantKey(field))),
  ),
};

String _fieldPath(String parent, ast.PatternField field) {
  final member = field.element;
  final name = field.effectiveName!;
  return '$parent/${name.startsWith('_') ? '${member!.library!.uri}:$name' : name}';
}

final class _Matcher(final FunctionContext context, final PatternCache cache) {
  Value? _require(Value value, ValueType type, JumpTarget? failure) {
    if (type.accepts(value.type)) {
      return context.normal(context.cast(value, type));
    }
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
    Map<VariableElement, Value> bindings, [
    String path = '',
  ]) {
    if (context.current == null) return;
    final value = context.refined(input);
    switch (pattern) {
      case ast.ParenthesizedPattern(:final pattern):
        match(pattern, value, failure, bindings, path);
      case ast.WildcardPattern(:final type):
        if (type != null) {
          _require(value, context.typeOf(type.type!, type), failure);
        }
      case ast.DeclaredVariablePattern():
        final variable = pattern.declaredFragment!.element;
        final bound = _require(
          value,
          context.typeOf(variable.type, pattern),
          failure,
        );
        if (bound != null) bindings[variable] = bound;
      case ast.AssignedVariablePattern(element: final VariableElement variable)
          when context.hasLocal(variable):
        final bound = _require(
          value,
          context.typeOf(variable.type, pattern),
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
          // The shape check uses Object? slots. Restore the analyzer's static
          // field type before lowering nested operators or binding variables.
          final checked = context.normal(
            context.cast(
              item,
              context.typeOf(field.pattern.matchedValueType!, field),
            ),
          );
          if (checked == null) return;
          match(
            field.pattern,
            checked,
            failure,
            bindings,
            '$path/${field.name == null ? '\$${slot + 1}' : field.effectiveName}',
          );
          if (context.current == null) return;
        }
      case ast.ObjectPattern(:final type, :final fields):
        final object = _require(
          value,
          context.typeOf(type.type!, type),
          failure,
        );
        if (object == null) return;
        for (final field in fields) {
          final member = field.element;
          if (member is! ExecutableElement ||
              member.isStatic ||
              member.enclosingElement is! ClassElement ||
              member.library.isDartCore) {
            unsupported(context.unit, field, 'object pattern member');
          }
          // Unlike record slots, even wildcard fields must evaluate their getter.
          final key = _fieldPath(path, field);
          final item = cache.read(
            key,
            () => member is MethodElement
                ? context.normal(
                    context.emit(
                      BindMethod(
                        context.bindings.target(member, context.unit, field),
                        object,
                      ),
                    ),
                  )
                : context.callPositionalMember(member, object, [], field),
          );
          if (item == null) return;
          final checked = context.normal(
            context.cast(
              item,
              context.typeOf(field.pattern.matchedValueType!, field),
            ),
          );
          if (checked == null) return;
          match(field.pattern, checked, failure, bindings, key);
          if (context.current == null) return;
        }
      case ast.ConstantPattern(:final expression):
        final constant = context.bindings.constantValue(
          expression.computeConstantValue()?.value,
          context.unit,
          expression,
        );
        final result = cache.read(
          cache.comparisonKey(path, 'constant==', expression),
          () => lowerEquality(context, constant, value),
        );
        if (result == null) return;
        context.guard(context.normal(context.cast(result, .boolean)), failure!);
      case ast.RelationalPattern(:final operand, :final operator):
        final constant = context.bindings.constantValue(
          operand.computeConstantValue()?.value,
          context.unit,
          operand,
        );
        final result = cache.read(
          cache.comparisonKey(path, operator.lexeme, operand),
          () => operator.lexeme == '==' || operator.lexeme == '!='
              ? lowerEquality(context, value, constant)
              : lowerBinary(context, pattern, operator, value, constant),
        );
        if (result == null) return;
        final checked = context.normal(context.cast(result, .boolean));
        if (checked == null) return;
        context.guard(
          operator.lexeme == '!='
              ? context.emit(Equals(checked, Constant.boolean(false)))
              : checked,
          failure!,
        );
      case ast.CastPattern(:final pattern, :final type):
        final cast = context.normal(
          context.cast(value, context.typeOf(type.type!, type)),
        );
        if (cast != null) match(pattern, cast, failure, bindings, path);
      case ast.NullAssertPattern(:final pattern):
        final checked = context.normal(context.checkNotNull(value));
        if (checked != null) match(pattern, checked, failure, bindings, path);
      case ast.NullCheckPattern(:final pattern):
        context.guard(
          context.testType(value, .nullType, negated: true),
          failure!,
        );
        match(pattern, value, failure, bindings, path);
      case ast.LogicalAndPattern(:final leftOperand, :final rightOperand):
        match(leftOperand, value, failure, bindings, path);
        match(rightOperand, value, failure, bindings, path);
      case ast.LogicalOrPattern():
        _or(pattern, value, failure!, bindings, path);
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
    Map<VariableElement, Value> bindings, [
    String path = '',
  ]) {
    Map<PatternVariableElement, Value> arm(
      ast.DartPattern operand,
      JumpTarget reject,
    ) {
      final values = <PatternVariableElement, Value>{};
      match(operand, value, reject, values, path);
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
      for (final variable in left.keys) context.typeOf(variable.type, pattern),
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
