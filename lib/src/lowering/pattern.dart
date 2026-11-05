import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'analyzer_metadata.dart';
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
  subject = _contextualCast(context, pattern, subject, failure);
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
  subject = _contextualCast(context, pattern, subject, null);
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

// Contextual dynamic casts precede all destructuring/getter effects. The
// analyzer's matchedValueType alone only describes the later pattern checks.
Value? _contextualCast(
  FunctionContext context,
  ast.DartPattern pattern,
  Value? subject,
  JumpTarget? failure,
) {
  if (failure == null && subject?.type == ValueType.dynamicType) {
    final type = patternContextType(pattern);
    if (type != null) {
      return context.normal(
        context.convert(subject!, context.typeOf(type, pattern)),
      );
    }
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
    void collect(ast.DartPattern pattern, Object path) {
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
            final key = _getterPath(
              path,
              field.name == null ? '\$${++index}' : field.effectiveName!,
            );
            collect(field.pattern, key);
          }
        case ast.ListPattern(:final elements):
          final rest = elements.indexWhere((e) => e is ast.RestPatternElement);
          if (elements.length != 1 || rest < 0) {
            final key = _getterPath(path, 'length');
            counts.update(key, (count) => count + 1, ifAbsent: () => 1);
          }
          for (final (index, element) in elements.indexed) {
            final child = switch (element) {
              ast.DartPattern() => element,
              ast.RestPatternElement(:final pattern) => pattern,
              _ => unsupported(context.unit, element, 'list pattern element'),
            };
            if (child == null || _isDiscard(child)) continue;
            final key = _listPath(path, index, rest, elements.length);
            counts.update(key, (count) => count + 1, ifAbsent: () => 1);
            collect(child, key);
          }
        case ast.MapPattern(:final elements):
          for (final element in elements) {
            if (element is! ast.MapPatternEntry) continue;
            final key = constantKey(constant(element.key));
            final lookup = (path, '[]', key);
            final contains = (path, 'containsKey', key);
            counts.update(lookup, (count) => count + 1, ifAbsent: () => 1);
            counts.update(contains, (count) => count + 1, ifAbsent: () => 1);
            collect(element.value, lookup);
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

  Constant constant(ast.Expression expression) =>
      context.bindings.constantValue(
        expression.computeConstantValue()?.value,
        context.unit,
        expression,
      );

  Object comparisonKey(Object path, String operator, ast.Expression operand) =>
      (
        path,
        operator == '!=' ? '==' : operator,
        constantKey(constant(operand)),
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

Object _fieldPath(Object parent, ast.PatternField field) {
  final member = field.element;
  final name = field.effectiveName!;
  return _getterPath(
    parent,
    name.startsWith('_') ? (member!.library!.uri, name) : name,
  );
}

Object _getterPath(Object parent, Object name) => (parent, name, null);

Object _listPath(Object parent, int index, int rest, int length) {
  if (index == rest) return (parent, 'sublist', (rest, length - rest - 1));
  // Tail positions are distinct from head indices, even if their runtime
  // numeric indices happen to coincide.
  if (rest >= 0 && index > rest) return (parent, 'tail[]', length - index - 1);
  return (parent, '[]', constantKey(Constant.integer(index)));
}

bool _isDiscard(ast.DartPattern pattern) =>
    pattern.unParenthesized is ast.WildcardPattern &&
    (pattern.unParenthesized as ast.WildcardPattern).type == null;

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
    Object path = '',
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
      case ast.ListPattern():
        _list(pattern, value, failure, bindings, path);
      case ast.MapPattern():
        _map(pattern, value, failure, bindings, path);
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
            _getterPath(
              path,
              field.name == null ? '\$${slot + 1}' : field.effectiveName!,
            ),
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
              (!isClassOrEnum(member.enclosingElement) &&
                  coreEnumField(member) == null)) {
            unsupported(context.unit, field, 'object pattern member');
          }
          // Unlike record slots, even wildcard fields must evaluate their getter.
          final key = _fieldPath(path, field);
          final item = cache.read(key, () {
            if (coreEnumField(member) case final slot?) {
              return context.normal(context.emit(LoadField(slot, object)));
            }
            if (member.library.isDartCore &&
                !coreSymbolMember(member, object.type)) {
              final operation = member is GetterElement
                  ? coreCollectionOperation(member.name!, object, [])
                  : null;
              if (operation == null) {
                unsupported(context.unit, field, 'core object pattern member');
              }
              return context.normal(context.emit(operation));
            }
            return member is MethodElement
                ? context.normal(
                    context.emit(
                      BindMethod(
                        context.bindings.target(member, context.unit, field),
                        object,
                      ),
                    ),
                  )
                : context.callPositionalMember(member, object, [], field);
          });
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

  void _condition(Value? condition, JumpTarget? failure) {
    if (condition == null) return;
    if (failure != null) {
      context.guard(condition, failure);
      return;
    }
    final success = JumpTarget(context);
    context.guard(
      context.emit(Equals(condition, const Constant.boolean(false))),
      success,
    );
    if (context.current != null) {
      context.normal(context.emit(PatternMatchFailure()));
    }
    success.enter();
  }

  Value? _cached(Object key, ValueType type, Value? Function() extract) {
    final value = cache.read(key, extract);
    return value == null ? null : context.normal(context.cast(value, type));
  }

  void _list(
    ast.ListPattern pattern,
    Value value,
    JumpTarget? failure,
    Map<VariableElement, Value> bindings,
    Object path,
  ) {
    final required = context.typeOf(pattern.requiredType!, pattern);
    final list = _require(value, required, failure);
    if (list == null) return;
    final elements = pattern.elements;
    final rest = elements.indexWhere((e) => e is ast.RestPatternElement);
    final count = elements.length - (rest < 0 ? 0 : 1);
    Value? length;
    if (rest < 0 || count > 0) {
      length = _cached(
        _getterPath(path, 'length'),
        .integer,
        () => context.normal(context.emit(CollectionLength(list))),
      );
      if (length == null) return;
      final size = Constant.integer(count);
      // Empty patterns also cover a misbehaving list with negative length.
      final condition = rest >= 0
          ? context.emit(IntBinary(.greaterOrEqual, length, size))
          : count == 0
          ? context.emit(IntBinary(.lessOrEqual, length, size))
          : context.emit(Equals(length, size));
      _condition(condition, failure);
      if (context.current == null) return;
    }
    for (final (index, element) in elements.indexed) {
      final child = switch (element) {
        ast.DartPattern() => element,
        ast.RestPatternElement(:final pattern) => pattern,
        _ => unsupported(context.unit, element, 'list pattern element'),
      };
      if (child == null || _isDiscard(child)) continue;
      final key = _listPath(path, index, rest, elements.length);
      final item = _cached(
        key,
        context.typeOf(child.matchedValueType!, child),
        () {
          if (index == rest) {
            final tail = elements.length - rest - 1;
            final end = tail == 0
                ? null
                : context.emit(
                    IntBinary(.subtract, length!, Constant.integer(tail)),
                  );
            return context.normal(
              context.emit(ListSublist(list, Constant.integer(rest), end)),
            );
          }
          final offset = rest >= 0 && index > rest
              ? context.emit(
                  IntBinary(
                    .subtract,
                    length!,
                    Constant.integer(elements.length - index),
                  ),
                )
              : Constant.integer(index);
          return context.normal(context.emit(CollectionGet(list, offset)));
        },
      );
      if (item == null) return;
      match(child, item, failure, bindings, key);
      if (context.current == null) return;
    }
  }

  void _map(
    ast.MapPattern pattern,
    Value value,
    JumpTarget? failure,
    Map<VariableElement, Value> bindings,
    Object path,
  ) {
    final required = context.typeOf(pattern.requiredType!, pattern);
    final map = _require(value, required, failure);
    if (map == null) return;
    final valueType = CoreTypes.view(required, CoreTypes.map)!.typeArguments[1];
    for (final element in pattern.elements) {
      if (element is! ast.MapPatternEntry) {
        unsupported(context.unit, element, 'map pattern element');
      }
      final constant = cache.constant(element.key);
      final key = constantKey(constant);
      final lookup = (path, '[]', key);
      final item = _cached(
        lookup,
        valueType.nullable,
        () => context.normal(context.emit(CollectionGet(map, constant))),
      );
      if (item == null) return;
      // A null lookup can denote a present entry only if the pattern's V
      // admits null. For a type variable this remains a runtime type test.
      final present = context.branch(
        context.testType(item, .nullType, negated: true),
        () => const Constant.boolean(true),
        () => context.branch(
          context.testType(const Constant.nullValue(), valueType),
          () => _cached(
            (path, 'containsKey', key),
            .boolean,
            () => context.normal(context.emit(MapContainsKey(map, constant))),
          ),
          () => const Constant.boolean(false),
          .boolean,
        ),
        .boolean,
      );
      _condition(present, failure);
      if (context.current == null) return;
      final checked = context.normal(
        context.cast(
          item,
          context.typeOf(element.value.matchedValueType!, element.value),
        ),
      );
      if (checked == null) return;
      match(element.value, checked, failure, bindings, lookup);
      if (context.current == null) return;
    }
  }

  void _or(
    ast.LogicalOrPattern pattern,
    Value value,
    JumpTarget failure,
    Map<VariableElement, Value> bindings, [
    Object path = '',
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
