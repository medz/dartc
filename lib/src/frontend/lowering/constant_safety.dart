import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'analyzer_metadata.dart';

/// Rejects constant dependencies whose identity, storage or value analyzer loses.
///
/// Inspect syntax before consuming even a scalar result: a private-symbol
/// comparison may already have folded to the wrong boolean or selected branch.
/// This deliberately visits both branches, without evaluating Dart expressions.
final class ConstantSafety() {
  void check(
    ResolvedUnitResult unit,
    AstNode site, {
    AstNode? syntax,
    VariableElement? variable,
  }) {
    final scan = _Scan();
    try {
      if (variable != null) scan.variable(variable);
      syntax?.accept(scan);
    } on _UnsafeConstant catch (error) {
      final location = unit.lineInfo.getLocation(site.offset);
      throw UnsupportedError(
        '${unit.uri}:${location.lineNumber}:${location.columnNumber}: '
        'IR lowering for constant safety: ${error.reason}',
      );
    }
  }
}

final class _UnsafeConstant(final String reason) implements Exception;

final class _Scan() extends RecursiveAstVisitor<void> {
  final visited = <(Element, bool)>{};
  bool _originalEvaluation = false;

  bool enter(Element element) => visited.add((element, _originalEvaluation));

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
    final original = _originalEvaluation;
    _originalEvaluation = true;
    try {
      _constructor(element);
    } finally {
      _originalEvaluation = original;
    }
  }

  void _constructor(ConstructorElement element) {
    element = element.baseElement;
    if (!enter(element) || element.library.isInSdk) return;
    if (!element.isConst || element.isExternal) {
      throw _UnsafeConstant(
        'unavailable const constructor metadata for '
        '${element.library.uri}::${element.displayName}',
      );
    }
    if (element.enclosingElement is EnumElement &&
        element.enclosingElement.fields.any(
          (field) =>
              !field.isStatic &&
              !field.isOriginGetterSetter &&
              field.name == '_name',
        )) {
      throw _UnsafeConstant(
        'enum instance field _name loses its value in analyzer constants',
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
  void visitAnnotation(Annotation node) {
    if (node.element case final ConstructorElement element) {
      constructor(element);
    }
    super.visitAnnotation(node);
  }

  ({num? value, bool integer, bool floating}) numericOperand(
    Expression expression,
  ) {
    if (expression case ParenthesizedExpression(:final expression)) {
      return numericOperand(expression);
    }
    if (expression case IntegerLiteral(:final value)) {
      return (value: value, integer: true, floating: false);
    }
    if (expression case DoubleLiteral(:final value)) {
      return (value: value, integer: false, floating: true);
    }
    if (expression case PrefixExpression(:final operator, :final operand)
        when operator.lexeme == '-') {
      final input = numericOperand(operand);
      return (
        value: input.value == null ? null : -input.value!,
        integer: input.integer,
        floating: input.floating,
      );
    }
    final element = switch (expression) {
      SimpleIdentifier(:final element) => element,
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    var type = expression.staticType;
    if (variable is VariableElement) {
      type ??= variable.type;
      if (variable.isConst) {
        final value = variable.computeConstantValue();
        if (value?.hasKnownValue == true) {
          final number = value!.toIntValue() ?? value.toDoubleValue();
          return (
            value: number,
            integer: number is int,
            floating: number is double,
          );
        }
      }
    }
    if (expression case InstanceCreationExpression(:final constructorName)) {
      type ??= constructorName.element?.enclosingElement.thisType;
    }
    if (expression is BooleanLiteral ||
        expression is NullLiteral ||
        expression is StringLiteral ||
        expression is SymbolLiteral ||
        expression is ListLiteral ||
        expression is SetOrMapLiteral ||
        expression is RecordLiteral) {
      return (value: null, integer: false, floating: false);
    }
    return (
      value: null,
      integer:
          type is! InterfaceType ||
          type.isDartCoreInt ||
          type.isDartCoreNum ||
          type.isDartCoreObject,
      floating:
          type is! InterfaceType ||
          type.isDartCoreDouble ||
          type.isDartCoreNum ||
          type.isDartCoreObject,
    );
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    super.visitBinaryExpression(node);
    if (!_originalEvaluation) return;
    if (!const {
      '==',
      '!=',
      '<',
      '<=',
      '>',
      '>=',
    }.contains(node.operator.lexeme)) {
      return;
    }
    final left = numericOperand(node.leftOperand),
        right = numericOperand(node.rightOperand);
    if (!(left.integer && right.floating || left.floating && right.integer)) {
      return;
    }
    final a = left.value, b = right.value;
    if (a != null && b != null) {
      if (a.isNaN || b.isNaN) return;
      final order = a == 0 && b == 0 ? 0 : a.compareTo(b);
      final roundedLeft = a.toDouble(), roundedRight = b.toDouble();
      final (expected, observed) = switch (node.operator.lexeme) {
        '==' => (order == 0, roundedLeft == roundedRight),
        '!=' => (order != 0, roundedLeft != roundedRight),
        '<' => (order < 0, roundedLeft < roundedRight),
        '<=' => (order <= 0, roundedLeft <= roundedRight),
        '>' => (order > 0, roundedLeft > roundedRight),
        _ => (order >= 0, roundedLeft >= roundedRight),
      };
      if (observed == expected) return;
    }
    // shortcut: reject unsafe constructor folds until their evaluator is replaced.
    throw _UnsafeConstant(
      'exact mixed numeric constant evaluation is not implemented',
    );
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
