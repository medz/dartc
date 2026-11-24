import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'accesses.dart';
import 'assigned.dart';
import 'builder.dart';
import 'calls.dart';
import 'checks.dart';
import 'conversions.dart';
import 'describe.dart';
import 'late_locals.dart';
import 'match_cache.dart';
import 'operators.dart';
import 'pattern_types.dart';
import 'records.dart';
import 'scope.dart';
import 'types.dart';

/// A value that patterns match, and how it was got from what they match first.
typedef Matched = ({HirValue value, DartType type, String path});

/// Translates patterns.
final class PatternTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final OperatorTranslator _operators,
  final CallTranslator _calls,
  final RecordTranslator _records,
  final LateTranslator _lates,
) {
  late final _conversions = Conversions(_scope, _builder);

  /// What the patterns translated now keep, the innermost last.
  final _caches = <MatchCache>[];

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Does [work], which matches [patterns] with the same value.
  T matching<T>(Iterable<DartPattern> patterns, T Function() work) {
    final cache = MatchCache(_builder, _conversions)
      ..prepare(repeatedIn(patterns));
    _caches.add(cache);
    final result = work();
    _caches.removeLast();
    return result;
  }

  /// A block where patterns in [node] go on, with [variables] that they set.
  Join join(AstNode node, [Iterable<Element> variables = const []]) => _builder
      .joinAll(node, const [], [..._caches.last.variables, ...variables]);

  /// Declares the variables that [patterns] set.
  void declareIn(Iterable<DartPattern> patterns) {
    for (final variable in patterns.expand(declaredIn)) {
      variable as VariableElement;
      final type =
          valueType(variable.type) ??
          _unsupported(patterns.first, 'a variable of type ${variable.type}');
      _builder.declare(variable, type);
    }
  }

  /// Goes on if [value], of [type], matches [guarded], and to [fail] if not.
  void match(GuardedPattern guarded, HirValue value, DartType type, Join fail) {
    declareIn([guarded.pattern]);
    final matched = (value: value, type: type, path: '');
    _match(guarded.pattern, matched, fail);
    if (guarded.whenClause case final clause?) {
      final boolType = _conversions.types.boolType;
      _unless(_evaluator.valueTo(clause.expression, boolType), fail);
    }
  }

  /// Does one of two parts of [node], depending on a [test], which is either a
  /// condition or a value and what it has to match.
  void choose(
    AstNode node,
    (Expression, CaseClause?) test,
    void Function() ifTrue,
    void Function() ifFalse,
  ) {
    final (expression, clause) = test;
    final exit = _builder.join(node);
    void part(void Function() work) {
      work();
      _builder.jump(exit);
    }

    if (clause == null) {
      final boolType = _conversions.types.boolType;
      _builder.branch(
        _evaluator.valueTo(expression, boolType),
        () => part(ifTrue),
        () => part(ifFalse),
      );
    } else {
      final value = _evaluator.value(expression);
      final guarded = clause.guardedPattern;
      matching([guarded.pattern], () {
        final other = join(node);
        match(guarded, value, expression.staticType!, other);
        part(ifTrue);
        _builder.enter(other);
        part(ifFalse);
      });
    }
    _builder.enter(exit);
  }

  /// Gives the variables of [pattern] what they are of [value], which is of
  /// [type] and matches.
  void destructure(DartPattern pattern, HirValue value, DartType type) =>
      matching(const [], () {
        declareIn([pattern]);
        final fail = join(pattern);
        final pending = _pending = [];
        final wanted = type is DynamicType
            ? PatternTypes(_builder.library).of(pattern)
            : null;
        final found = wanted == null
            ? value
            : _cast(pattern, value, type, wanted);
        _match(pattern, (value: found, type: wanted ?? type, path: ''), fail);
        _pending = null;
        for (final assign in pending) {
          assign();
        }
        final done = join(pattern, declaredIn(pattern));
        _builder
          ..jump(done)
          ..enter(fail);
        _builder
          ..call(HirCall(_scope.runtime('throwNoMatch'), const []))
          ..end(HirUnreachable());
        _builder.enter(done);
      });

  /// What assigns variables once everything matches.
  List<void Function()>? _pending;

  /// Goes to [fail] unless [condition] holds.
  void _unless(HirValue condition, Join fail) =>
      _builder.branch(_not(condition), () => _builder.jump(fail), () {});

  void _match(DartPattern pattern, Matched matched, Join fail) {
    final (:value, :type, :path) = matched;
    switch (pattern) {
      case ParenthesizedPattern(:final pattern):
        _match(pattern, matched, fail);
      case WildcardPattern():
        if (pattern.type?.type case final wanted?) {
          _testFor(pattern, matched, wanted, fail);
        }
      case DeclaredVariablePattern():
        _declare(pattern, matched, fail);
      case AssignedVariablePattern():
        _assign(pattern, matched, fail);
      case NullCheckPattern(:final pattern):
        if (value.type == .reference) {
          _unless(_not(_conversions.isNull(value)), fail);
        }
        final found = (value: value, type: _nonNull(type), path: path);
        _match(pattern, found, fail);
      case NullAssertPattern(:final pattern):
        final found = CheckedOperations(_scope, _builder).notNull(value);
        final some = (value: found, type: _nonNull(type), path: path);
        _match(pattern, some, fail);
      case CastPattern(:final pattern, type: TypeAnnotation(type: final to!)):
        final found = _conversions.cast(
          value,
          type,
          to,
          ending: ' in type cast',
        );
        if (found == null) _unsupported(pattern, 'testing for $to');
        _match(pattern, (value: found, type: to, path: path), fail);
      case ConstantPattern(:final expression):
        final constant = (_evaluator.value(expression), expression.staticType!);
        final equal = _operators.binary(pattern, '==', constant, (value, type));
        _unless(equal, fail);
      case RelationalPattern():
        _relation(pattern, matched, fail);
      case LogicalAndPattern(:final leftOperand, :final rightOperand):
        _match(leftOperand, matched, fail);
        // What the first test shows, the second can rely on.
        final own = rightOperand.matchedValueType ?? type;
        _match(rightOperand, (
          value: _conversions.narrow(value, _valueType(pattern, own)),
          type: own,
          path: path,
        ), fail);
      case LogicalOrPattern(:final leftOperand, :final rightOperand):
        final next = join(pattern);
        final found = join(pattern, declaredIn(pattern));
        _match(leftOperand, matched, next);
        _builder
          ..jump(found)
          ..enter(next);
        _match(rightOperand, matched, fail);
        _builder
          ..jump(found)
          ..enter(found);
      case RecordPattern():
        _record(pattern, matched, fail);
      case ObjectPattern():
        _object(pattern, matched, fail);
      case ListPattern():
        _list(pattern, matched, fail);
      case MapPattern():
        _map(pattern, matched, fail);
    }
  }

  HirValue _not(HirValue value) => _builder.add(HirUnary(.not, value));

  DartType _nonNull(DartType type) =>
      _builder.library.typeSystem.promoteToNonNull(type);

  HirType _valueType(AstNode node, DartType type) =>
      valueType(type) ?? _unsupported(node, 'a value of type $type');

  /// Goes to [fail] unless [matched] is of [wanted]. Gives it as that.
  Matched _testFor(AstNode node, Matched matched, DartType wanted, Join fail) {
    final (:value, :type, :path) = matched;
    final representation = _valueType(node, wanted);
    if (_pending != null && type is DynamicType) {
      return (
        value: _cast(node, value, type, wanted),
        type: wanted,
        path: path,
      );
    }
    final isSure =
        type is! DynamicType &&
        _builder.library.typeSystem.isSubtypeOf(
          type.extensionTypeErasure,
          wanted.extensionTypeErasure,
        );
    if (!isSure) {
      final test =
          _conversions.isInstance(value, wanted) ??
          _unsupported(node, 'testing for $wanted');
      _unless(test, fail);
    }
    return (
      value: _conversions.narrow(value, representation),
      type: isSure ? type : wanted,
      path: path,
    );
  }

  HirValue _cast(AstNode node, HirValue value, DartType from, DartType to) =>
      _conversions.cast(value, from, to) ??
      _unsupported(node, 'testing for $to');

  void _declare(DeclaredVariablePattern pattern, Matched matched, Join fail) {
    final variable = pattern.declaredFragment!.element, type = variable.type;
    final found = pattern.type == null
        ? matched
        : _testFor(pattern, matched, type, fail);
    final value = _conversions.coerce(found.value, _valueType(pattern, type));
    _builder.assign(variable, value);
  }

  void _assign(AssignedVariablePattern pattern, Matched matched, Join fail) {
    final variable = pattern.element! as VariableElement;
    final (:value, :type, path: _) = matched;
    final found = _cast(pattern, value, type, variable.type);
    void assign() {
      if (!_lates.write(variable, found)) _builder.assign(variable, found);
    }

    _pending!.add(assign);
  }

  void _relation(RelationalPattern pattern, Matched matched, Join fail) {
    final operand = pattern.operand;
    final right = (_evaluator.value(operand), operand.staticType!);
    final result = _operators.binary(pattern, pattern.operator.lexeme, (
      matched.value,
      matched.type,
    ), right);
    final types = _conversions.types;
    _unless(
      result.type == .reference
          ? _conversions.cast(result, types.dynamicType, types.boolType)!
          : result,
      fail,
    );
  }

  /// What [compute] gives, of [type], which is the same wherever it is got as
  /// [key] tells from [from].
  Matched _read(
    AstNode node,
    Matched from,
    String key,
    DartType type,
    HirValue Function() compute,
  ) {
    final path = '${from.path}$key';
    return (
      value: _caches.last.read(node, path, _valueType(node, type), compute),
      type: type,
      path: path,
    );
  }

  void _record(RecordPattern pattern, Matched matched, Join fail) {
    final (:value, :type, :path) = matched;
    final names = [for (final field in pattern.fields) ?field.effectiveName]
      ..sort();
    final object = _conversions.coerce(value, .reference);
    final own = boundOf(type), count = pattern.fields.length - names.length;
    final fits =
        own is RecordType &&
        type.nullabilitySuffix == .none &&
        own.positionalFields.length == count &&
        '${fieldNames(own)}' == '$names';
    if (!fits) {
      final test = _builder.call(
        HirCall(_scope.runtime('hasShape'), [
          object,
          _builder.add(HirConst(pattern.fields.length)),
          _builder.add(_scope.names(names)),
        ]),
      )!;
      _pending == null || type is! DynamicType
          ? _unless(test, fail)
          : _builder.unless(test, () => _throwNoRecord(object, count, names));
    }
    var position = 0;
    for (final field in pattern.fields) {
      final name = field.effectiveName;
      final index = name == null ? position++ : count + names.indexOf(name);
      final element = _builder.add(
        HirLoadElement(.reference, object, _builder.add(HirConst(index))),
      );
      final found = fits
          ? fieldTypes(own)[index]
          : _conversions.types.objectQuestionType;
      _match(field.pattern, (
        value: _conversions.coerce(element, _valueType(field, found)),
        type: found,
        path: '$path.${name ?? '\$${index + 1}'}',
      ), fail);
    }
  }

  /// Throws because [value] is no record of [count] fields and [names].
  void _throwNoRecord(HirValue value, int count, List<String> names) {
    final named = names.map((name) => 'dynamic $name').join(', ');
    final fields = [
      for (var i = 0; i < count; i++) 'dynamic',
      if (names.isNotEmpty) '{$named}',
    ];
    _builder.call(
      HirCall(_scope.runtime('throwCast'), [
        value,
        _builder.add(_scope.text('(${fields.join(', ')})')),
        _builder.add(_scope.text('')),
      ]),
    );
  }

  void _object(ObjectPattern pattern, Matched given, Join fail) {
    final type = pattern.type.type!;
    final matched = _testFor(pattern, given, type, fail);
    for (final field in pattern.fields) {
      if (ignoresField(field.pattern)) continue;
      final found = _field(field, (
        value: matched.value,
        type: type,
        path: matched.path,
      ));
      _match(field.pattern, found, fail);
    }
  }

  Matched _field(PatternField field, Matched object) {
    final (:value, :type, :path) = object;
    final name = field.effectiveName!, element = field.element;
    if (_records.field(value, type, name) case final found?) {
      final types = fieldTypes(boundOf(type) as RecordType);
      return (
        value: found,
        type: types[fieldIndex(type, name)!],
        path: '$path.$name',
      );
    }
    if (type is DynamicType || element is! ExecutableElement) {
      _unsupported(field, describe(field));
    }
    final result = element is GetterElement ? element.returnType : element.type;
    return _read(field, object, accessKey(field), result, () {
      return _calls.read(field, (value, type), element);
    });
  }

  HirValue _use(
    AstNode node,
    Matched object,
    ExecutableElement member, [
    List<HirValue> arguments = const [],
  ]) => _calls.invoke(node, object.value, object.type, member, arguments)!;

  void _list(ListPattern pattern, Matched given, Join fail) {
    final type = pattern.requiredType! as InterfaceType;
    final matched = _testFor(pattern, given, type, fail);
    final list = (value: matched.value, type: type, path: matched.path);
    final elements = pattern.elements;
    final rest = elements.indexWhere((e) => e is RestPatternElement);
    final least = elements.length - (rest < 0 ? 0 : 1);
    HirValue integer(int value) => _builder.add(HirConst(value));
    HirValue? counted;
    HirValue length() => counted ??= _read(
      pattern,
      list,
      '.length',
      _conversions.types.intType,
      () => _use(pattern, list, _listMember.getGetter('length')!),
    ).value;
    if (rest < 0 || least > 0) {
      final relation = rest < 0
          ? HirRelation.equal
          : HirRelation.greaterOrEqual;
      _unless(
        _builder.add(HirCompare(relation, length(), integer(least))),
        fail,
      );
    }
    final own = type.typeArguments.single;
    for (final (i, element) in elements.indexed) {
      if (element is RestPatternElement) {
        final inner = element.pattern;
        if (inner == null || ignoresValue(inner)) continue;
        final after = elements.length - i - 1;
        final key = listKey(elements, i, rest);
        final found = _read(element, list, key, type, () {
          HirValue end() => _conversions.coerce(
            _builder.add(HirIntBinary(.subtract, length(), integer(after))),
            .reference,
          );
          final method = _listMember.getMethod('sublist')!;
          return _use(element, list, method, [
            integer(i),
            if (after > 0) end(),
          ]);
        });
        _match(inner, found, fail);
        continue;
      }
      element as DartPattern;
      if (ignoresValue(element)) continue;
      final isLate = rest >= 0 && i > rest;
      final fromEnd = elements.length - i;
      final key = listKey(elements, i, rest);
      final found = _read(element, list, key, own, () {
        final at = isLate
            ? _builder.add(HirIntBinary(.subtract, length(), integer(fromEnd)))
            : integer(i);
        return _use(element, list, _listMember.getMethod('[]')!, [at]);
      });
      _match(element, found, fail);
    }
  }

  InterfaceElement get _listMember => _conversions.types.listElement;

  void _map(MapPattern pattern, Matched given, Join fail) {
    final type = pattern.requiredType! as InterfaceType;
    final matched = _testFor(pattern, given, type, fail);
    final map = (value: matched.value, type: type, path: matched.path);
    final own = type.typeArguments.last;
    final nullable = _builder.library.typeSystem.leastUpperBound(
      own,
      _conversions.types.nullType,
    );
    final mapClass = _conversions.types.mapElement;
    for (final entry in pattern.elements.whereType<MapPatternEntry>()) {
      HirValue key() => _evaluator.valueAsObject(
        entry.key,
        _conversions.types.objectQuestionType,
      );
      final found = _read(entry, map, mapKey(entry), nullable, () {
        return _use(entry, map, mapClass.getMethod('[]')!, [key()]);
      });
      final isMissing = _builder.joinAll(entry, const [], [
        ..._caches.last.variables,
      ]);
      final isThere = join(entry);
      _builder.branch(
        _conversions.isNull(_conversions.coerce(found.value, .reference)),
        () => _builder.jump(isMissing),
        () => _builder.jump(isThere),
      );
      _builder.enter(isMissing);
      final isIn = _read(
        entry,
        map,
        '${mapKey(entry)}?',
        _conversions.types.boolType,
        () => _use(entry, map, mapClass.getMethod('containsKey')!, [key()]),
      );
      _unless(isIn.value, fail);
      final fits =
          _conversions.isInstance(
            _conversions.coerce(found.value, .reference),
            own,
          ) ??
          _unsupported(entry, 'testing for $own');
      _unless(fits, fail);
      _builder
        ..jump(isThere)
        ..enter(isThere);
      final value = _conversions.coerce(found.value, _valueType(entry, own));
      _match(entry.value, (value: value, type: own, path: found.path), fail);
    }
  }

  /// The value of [node], of [type].
  HirValue switchExpression(SwitchExpression node, DartType type) {
    final value = _evaluator.value(node.expression);
    final representation = valueType(type)!;
    final exit = _builder.join(node, representation);
    final patterns = node.cases.map((member) => member.guardedPattern.pattern);
    matching(patterns, () {
      for (final member in node.cases) {
        final next = join(node);
        match(member.guardedPattern, value, node.expression.staticType!, next);
        _builder
          ..jump(exit, _evaluator.valueTo(member.expression, type))
          ..enter(next);
      }
    });
    _builder.end(HirUnreachable());
    return _builder.enter(exit)!;
  }
}
