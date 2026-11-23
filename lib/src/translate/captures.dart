import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'assigned.dart';

/// Which variables the closures inside one declaration use.
///
/// The initializer of a `late` local variable, which is evaluated later, counts
/// as a closure, and is told by the variable's declaration.
final class Captures._(
  final Map<AstNode, Set<Element>> _captured,
  final Set<Element> _cells,
) {
  factory of(AstNode declaration) {
    final visitor = _Captures();
    declaration.accept(visitor);
    final used = {for (final elements in visitor.captured.values) ...elements};
    return Captures._(visitor.captured, {
      for (final variable in assignedIn(declaration))
        if (!variable.isLate && used.contains(variable)) variable,
    });
  }

  /// The outer variables and local functions that [closure] uses.
  List<Element> usedBy(AstNode closure) => [...?_captured[closure]];

  /// Whether closures share changes of [variable].
  bool isCell(Element variable) => _cells.contains(variable);
}

final class _Captures() extends RecursiveAstVisitor<void> {
  final captured = <AstNode, Set<Element>>{};

  /// The closures around, and where each element is declared among them.
  final _closures = <AstNode>[];
  final _depths = <Element, int>{};

  void _declare(Element? element) {
    if (element != null) _depths[element] = _closures.length;
  }

  void _use(Element? element) {
    final depth = _depths[element];
    if (depth == null) return;
    for (final closure in _closures.skip(depth)) {
      captured[closure]!.add(element!);
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // The function of a declaration outside of any other is no closure.
    final parent = node.parent;
    final isClosure =
        parent is! FunctionDeclaration ||
        parent.parent is FunctionDeclarationStatement;
    void visit() => super.visitFunctionExpression(node);
    isClosure ? _within(node, visit) : visit();
  }

  void _within(AstNode closure, void Function() visit) {
    captured[closure] = {};
    _closures.add(closure);
    visit();
    _closures.removeLast();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is FunctionDeclarationStatement) {
      _declare(node.declaredFragment?.element);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    _declare(element);
    void visit() => super.visitVariableDeclaration(node);
    final isLater =
        element is LocalVariableElement &&
        element.isLate &&
        node.initializer != null;
    isLater ? _within(node, visit) : visit();
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _declare(node.declaredFragment?.element);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _declare(node.declaredFragment?.element);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _declare(node.declaredFragment?.element);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      _declare(parameter.declaredFragment?.element);
    }
    super.visitFormalParameterList(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _use(node.element);
    super.visitSimpleIdentifier(node);
  }

  void _useWritten(CompoundAssignmentExpression node) {
    _use(node.writeElement);
    _use(node.readElement);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _useWritten(node);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _useWritten(node);
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _useWritten(node);
    super.visitPostfixExpression(node);
  }
}

/// The member or top-level declaration that [node] is part of.
AstNode declarationOf(AstNode node) {
  var found = node;
  while (found.parent is! CompilationUnit &&
      found.parent is! ClassBody &&
      found.parent != null) {
    found = found.parent!;
  }
  return found;
}
