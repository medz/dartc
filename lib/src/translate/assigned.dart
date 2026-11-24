import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// The variable that [element], which a pattern can declare, is the same as.
///
/// Patterns of which one matches declare the same variables.
Element variableOf(Element element) {
  var found = element;
  while (found is PatternVariableElement) {
    final join = found.join;
    if (join == null) break;
    found = join;
  }
  return found;
}

/// The variables that [pattern] declares.
Set<Element> declaredIn(DartPattern pattern) {
  final visitor = _Declared();
  pattern.accept(visitor);
  return visitor.variables;
}

final class _Declared() extends RecursiveAstVisitor<void> {
  final variables = <Element>{};

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) =>
      variables.add(variableOf(node.declaredFragment!.element));
}

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
    if (element is VariableElement) {
      variables.add(variableOf(element) as VariableElement);
    }
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    final element = node.element;
    if (element is VariableElement) {
      variables.add(variableOf(element) as VariableElement);
    }
  }

  @override
  void visitForEachPartsWithIdentifier(ForEachPartsWithIdentifier node) {
    final element = node.identifier.element;
    if (element is VariableElement) {
      variables.add(variableOf(element) as VariableElement);
    }
    super.visitForEachPartsWithIdentifier(node);
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
