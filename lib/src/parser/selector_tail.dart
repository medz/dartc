import 'package:dartc/ast.dart';
import 'package:dartc/scanner.dart';

// A path in a real parsed tree, from its result back to the leading list.
// Argument, index, property-name and type subtrees are independent of that
// receiver. A null-aware index on this path would change its parsing context.
final class SelectorTail._(
  final List<Expression> _path,
  final int cursor,
  final Token current,
) {
  Expression apply(Expression receiver) {
    var result = receiver;
    for (var i = _path.length - 1; i >= 0; i--) {
      final node = _path[i];
      result = switch (node) {
        PropertyAccessExpression(:final property, :final isNullAware) =>
          PropertyAccessExpression(
            source: receiver.source,
            start: receiver.start,
            end: node.end,
            target: result,
            property: property,
            isNullAware: isNullAware,
          ),
        InvocationExpression(:final arguments, :final typeArguments) =>
          InvocationExpression(
            source: receiver.source,
            start: receiver.start,
            end: node.end,
            callee: result,
            arguments: arguments,
            typeArguments: typeArguments,
          ),
        IndexExpression(:final index, isNullAware: false) => IndexExpression(
          source: receiver.source,
          start: receiver.start,
          end: node.end,
          target: result,
          index: index,
        ),
        NullAssertionExpression() => NullAssertionExpression(
          source: receiver.source,
          start: receiver.start,
          end: node.end,
          operand: result,
        ),
        TypeInstantiationExpression(:final typeArguments) =>
          TypeInstantiationExpression(
            source: receiver.source,
            start: receiver.start,
            end: node.end,
            expression: result,
            typeArguments: typeArguments,
          ),
        _ => throw StateError('Not a receiver-independent selector.'),
      };
    }
    return result;
  }

  static SelectorTail? capture(
    Expression expression, {
    required int receiverStart,
    required int receiverEnd,
    required int cursor,
    required Token current,
  }) {
    final path = <Expression>[];
    var node = expression;
    while (true) {
      final receiver = switch (node) {
        PropertyAccessExpression(:final target) => target,
        InvocationExpression(:final callee) => callee,
        IndexExpression(:final target, isNullAware: false) => target,
        NullAssertionExpression(:final operand) => operand,
        TypeInstantiationExpression(:final expression) => expression,
        _ => null,
      };
      if (receiver == null) break;
      path.add(node);
      node = receiver;
    }
    if (path.isNotEmpty &&
        node is CollectionExpression &&
        node.start == receiverStart &&
        node.end == receiverEnd) {
      return SelectorTail._(path, cursor, current);
    }
    return null;
  }
}
