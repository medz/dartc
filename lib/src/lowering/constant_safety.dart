import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'analyzer_metadata.dart';

/// Rejects constant dependencies whose private-symbol identity analyzer loses.
///
/// Inspect syntax before consuming even a scalar result: a private-symbol
/// comparison may already have folded to the wrong boolean or selected branch.
/// This deliberately visits both branches, without evaluating Dart expressions.
final class ConstantSafety() {
  final _safe = <Element>{};
  final _safeExpressions = <Expression>{};

  void check(
    ResolvedUnitResult unit,
    AstNode site, {
    Expression? expression,
    VariableElement? variable,
  }) {
    if ((variable == null || _safe.contains(variable.baseElement)) &&
        (expression == null || _safeExpressions.contains(expression))) {
      return;
    }
    final scan = _Scan(_safe);
    try {
      if (variable != null) scan.variable(variable);
      expression?.accept(scan);
    } on _UnsafeConstant catch (error) {
      final location = unit.lineInfo.getLocation(site.offset);
      throw UnsupportedError(
        '${unit.uri}:${location.lineNumber}:${location.columnNumber}: '
        'IR lowering for constant safety: ${error.reason}',
      );
    }
    // Commit only after the entire reachable graph succeeds. A back edge must
    // never make a node safe while an ancestor is still being inspected.
    _safe.addAll(scan.visited);
    if (expression != null) _safeExpressions.add(expression);
  }
}

final class _UnsafeConstant(final String reason) implements Exception;

final class _Scan(final Set<Element> safe) extends RecursiveAstVisitor<void> {
  final visited = <Element>{};

  bool enter(Element element) =>
      !safe.contains(element) && visited.add(element);

  void variable(VariableElement element) {
    element = element.baseElement as VariableElement;
    if (!enter(element)) return;
    final initializer = element.constantInitializer;
    if (initializer != null) {
      initializer.accept(this);
    } else if (element is SuperFormalParameterElement &&
        element.hasDefaultValue) {
      final inherited = element.superConstructorParameter;
      if (inherited == null) {
        throw _UnsafeConstant(
          'unavailable inherited default for '
          '${element.library!.uri}::${element.name}',
        );
      }
      variable(inherited);
    } else if ((element.isConst ||
            element is FormalParameterElement && element.hasDefaultValue) &&
        !element.library!.isInSdk) {
      throw _UnsafeConstant(
        'unavailable initializer for ${element.library!.uri}::${element.name}',
      );
    }
  }

  void constructor(ConstructorElement element) {
    element = element.baseElement;
    if (!enter(element) || element.library.isInSdk) return;
    if (!element.isConst || element.isExternal) {
      throw _UnsafeConstant(
        'unavailable const constructor metadata for '
        '${element.library.uri}::${element.displayName}',
      );
    }
    for (final parameter in element.formalParameters) {
      variable(parameter);
    }
    if (element.redirectedConstructor case final redirect?) {
      constructor(redirect);
    }
    if (!element.isFactory) {
      for (final field in element.enclosingElement.fields) {
        if (!field.isStatic) variable(field);
      }
      if (element.superConstructor case final parent?) constructor(parent);
    }
    final initializers = constantConstructorInitializers(element);
    if (initializers == null) {
      throw _UnsafeConstant(
        'unavailable const constructor initializers for '
        '${element.library.uri}::${element.displayName}',
      );
    }
    for (final initializer in initializers) {
      initializer.accept(this);
    }
  }

  void reference(Element? element) {
    if (element is PropertyAccessorElement && element.variable.isConst) {
      variable(element.variable);
    } else if (element is VariableElement && element.isConst) {
      variable(element);
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    reference(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    final name = node.components.map((token) => token.lexeme).join('.');
    if (name.startsWith('_')) {
      throw _UnsafeConstant(
        'private Symbol literal #$name in constant dependencies',
      );
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.element;
    if (element == null) {
      throw _UnsafeConstant('unresolved constant constructor');
    }
    constructor(element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    final element = node.element;
    if (element == null) {
      throw _UnsafeConstant('unresolved constant constructor');
    }
    constructor(element);
    super.visitDotShorthandConstructorInvocation(node);
  }

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) {
    reference(node.propertyName.element);
    super.visitDotShorthandPropertyAccess(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    final element = node.element;
    if (element == null) throw _UnsafeConstant('unresolved super constructor');
    constructor(element);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    final element = node.element;
    if (element == null) {
      throw _UnsafeConstant('unresolved redirect constructor');
    }
    constructor(element);
    super.visitRedirectingConstructorInvocation(node);
  }
}
