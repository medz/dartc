import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';

/// Whether [node] is skipped where its target is null.
///
/// The first section of a cascade is not, as the whole cascade is.
bool isShorting(AstNode node) => switch (node) {
  MethodInvocation(:final operator?) ||
  PropertyAccess(:final operator) => operator.type == TokenType.QUESTION_PERIOD,
  IndexExpression(:final question) => question != null,
  _ => false,
};

/// Translates chains of accesses, calls and assignments, which end with null
/// where one of them finds null.
final class ChainTranslator(final FunctionBuilder _builder) {
  /// The parts of the chains being translated.
  final _parts = <Expression>{};

  /// Where each of those goes when it finds null, and what it gives there.
  final _exits = <(Join, HirType?)>[];

  /// What [node] uses first, if that is part of the same chain.
  static Expression? _before(Expression node) => switch (node) {
    MethodInvocation(:final target) ||
    PropertyAccess(:final target) ||
    IndexExpression(:final target) => target,
    FunctionExpressionInvocation(:final function) ||
    FunctionReference(:final function) => function,
    AssignmentExpression(:final leftHandSide) => leftHandSide,
    PostfixExpression(:final operand) => operand,
    PrefixExpression(
      operator: Token(type: TokenType.PLUS_PLUS || TokenType.MINUS_MINUS),
      :final operand,
    ) =>
      operand,
    _ => null,
  };

  static List<Expression> _chain(Expression node) => [
    for (Expression? part = node; part != null; part = _before(part)) part,
  ];

  /// Whether [node] is the whole of a chain that can end early.
  bool isWhole(Expression node) =>
      !_parts.contains(node) && _chain(node).any(isShorting);

  /// Does [work], which translates the chain [node] and gives a [result].
  HirValue? translate(
    Expression node,
    HirType? result,
    HirValue? Function() work,
  ) {
    final chain = _chain(node);
    final exit = _builder.join(node, result);
    _parts.addAll(chain);
    _exits.add((exit, result));
    _builder.jump(exit, work());
    _exits.removeLast();
    _parts.removeAll(chain);
    return _builder.enter(exit);
  }

  /// Ends the chain if [value], the target of [node], is null.
  void check(AstNode node, HirValue value) {
    if (!isShorting(node) || value.type != .reference) return;
    final (exit, result) = _exits.last;
    // A chain that gives a number never ends early.
    if (result != null && result != .reference) return;
    _builder.branch(
      _builder.add(HirCompare(.equal, value, _builder.add(HirNull()))),
      () =>
          _builder.jump(exit, result == null ? null : _builder.add(HirNull())),
      () {},
    );
  }
}
