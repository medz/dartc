import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// The local variables and parameters assigned anywhere in [node], in order.
Set<VariableElement> assignedIn(AstNode node) {
  final visitor = _Assigned();
  node.accept(visitor);
  return visitor.variables;
}

final class _Assigned() extends RecursiveAstVisitor<void> {
  final variables = <VariableElement>{};

  void _add(CompoundAssignmentExpression expression) {
    final element = expression.writeElement;
    if (element is VariableElement) variables.add(element);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _add(node);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _add(node);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _add(node);
    super.visitPostfixExpression(node);
  }
}
