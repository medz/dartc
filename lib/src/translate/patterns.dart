import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'checks.dart';
import 'conversions.dart';
import 'describe.dart';
import 'operators.dart';
import 'scope.dart';
import 'types.dart';

/// Translates patterns.
final class PatternTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final Evaluator _evaluator,
  final OperatorTranslator _operators,
) {
  late final _conversions = Conversions(_scope, _builder);

  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  /// Goes on if [value], of [type], matches [guarded], and to [fail] if not.
  void match(GuardedPattern guarded, HirValue value, DartType type, Join fail) {
    _match(guarded.pattern, value, type, fail);
    if (guarded.whenClause case final clause?) {
      final boolType = _conversions.types.boolType;
      _unless(_evaluator.valueTo(clause.expression, boolType), fail);
    }
  }

  /// Goes to [fail] unless [condition] holds.
  void _unless(HirValue condition, Join fail) => _builder.branch(
    _builder.add(HirUnary(.not, condition)),
    () => _builder.jump(fail),
    () {},
  );

  void _match(DartPattern pattern, HirValue value, DartType type, Join fail) {
    switch (pattern) {
      case ParenthesizedPattern(:final pattern):
        _match(pattern, value, type, fail);
      case WildcardPattern(type: null):
        break;
      case WildcardPattern(type: TypeAnnotation(type: final DartType wanted)):
        _unless(_isInstance(pattern, value, wanted), fail);
      case DeclaredVariablePattern():
        _declare(pattern, value, fail);
      case NullCheckPattern(:final pattern):
        if (value.type == .reference) {
          _unless(_not(_conversions.isNull(value)), fail);
        }
        _match(pattern, value, _nonNull(type), fail);
      case NullAssertPattern(:final pattern):
        final found = CheckedOperations(_scope, _builder).notNull(value);
        _match(pattern, found, _nonNull(type), fail);
      case CastPattern(:final pattern, type: TypeAnnotation(type: final to!)):
        final found = _conversions.cast(
          value,
          type,
          to,
          ending: ' in type cast',
        );
        if (found == null) _unsupported(pattern, 'testing for $to');
        _match(pattern, found, to, fail);
      case ConstantPattern(:final expression):
        final constant = (_evaluator.value(expression), expression.staticType!);
        final equal = _operators.binary(pattern, '==', constant, (value, type));
        _unless(equal, fail);
      case RelationalPattern():
        _relation(pattern, value, type, fail);
      case LogicalAndPattern(:final leftOperand, :final rightOperand):
        _match(leftOperand, value, type, fail);
        _match(rightOperand, value, type, fail);
      case LogicalOrPattern(:final leftOperand, :final rightOperand):
        final next = _builder.join(pattern), found = _builder.join(pattern);
        _match(leftOperand, value, type, next);
        _builder
          ..jump(found)
          ..enter(next);
        _match(rightOperand, value, type, fail);
        _builder
          ..jump(found)
          ..enter(found);
      default:
        _unsupported(pattern, describe(pattern));
    }
  }

  HirValue _not(HirValue value) => _builder.add(HirUnary(.not, value));

  DartType _nonNull(DartType type) =>
      _builder.library.typeSystem.promoteToNonNull(type);

  HirValue _isInstance(AstNode node, HirValue value, DartType type) =>
      _conversions.isInstance(value, type) ??
      _unsupported(node, 'testing for $type');

  void _declare(DeclaredVariablePattern pattern, HirValue value, Join fail) {
    final variable = pattern.declaredFragment!.element, type = variable.type;
    final representation =
        valueType(type) ?? _unsupported(pattern, 'a variable of type $type');
    if (pattern.type != null) _unless(_isInstance(pattern, value, type), fail);
    _builder
      ..declare(variable, representation)
      ..assign(variable, _conversions.coerce(value, representation));
  }

  void _relation(
    RelationalPattern pattern,
    HirValue value,
    DartType type,
    Join fail,
  ) {
    final operand = pattern.operand;
    final right = (_evaluator.value(operand), operand.staticType!);
    final result = _operators.binary(pattern, pattern.operator.lexeme, (
      value,
      type,
    ), right);
    _unless(result, fail);
  }

  /// The value of [node], of [type].
  HirValue switchExpression(SwitchExpression node, DartType type) {
    final value = _evaluator.value(node.expression);
    final representation = valueType(type)!;
    final exit = _builder.join(node, representation);
    for (final member in node.cases) {
      final next = _builder.join(node);
      match(member.guardedPattern, value, node.expression.staticType!, next);
      _builder
        ..jump(exit, _evaluator.valueTo(member.expression, type))
        ..enter(next);
    }
    _builder.end(HirUnreachable());
    return _builder.enter(exit)!;
  }
}
