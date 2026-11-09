// The pinned analyzer evaluator consumes its canonical, experimental AST API.
// ignore_for_file: experimental_member_use

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/listener.dart';

// Analyzer 14.7 does not expose a constant-evaluation override publicly.
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/ast.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/utilities.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/evaluation.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/value.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/element.dart' as internal;

import 'constant_safety.dart';

/// Evaluates checked constant syntax with exact mixed numeric comparisons.
final class ConstantEvaluation() {
  final _safety = ConstantSafety();
  final _values = <VariableElement, internal.Constant?>{};
  final _active = <VariableElement>{};

  DartObject? variable(
    VariableElement variable,
    ResolvedUnitResult unit,
    AstNode site,
  ) {
    _safety.check(unit, site, variable: variable);
    return _value(_variable(variable), unit, site);
  }

  DartObject? expression(ResolvedUnitResult unit, Expression expression) {
    var node = NodeLocator2(
      expression.offset,
      expression.end - 1,
    ).searchWithin(unit.unit);
    while (node != null) {
      if (node is internal.ExpressionImpl &&
          identical(internal.V1Projection.toV1Expression(node), expression)) {
        final result = _Visitor(
          this,
          unit.libraryElement as internal.LibraryElementImpl,
        ).evaluateConstant(node);
        if (result is! internal.DartObjectImpl) return null;
        _safety.check(unit, expression, syntax: expression);
        return result;
      }
      node = node.parent2;
    }
    throw UnsupportedError('Analyzer constant syntax is unavailable.');
  }

  DartObject? annotation(ResolvedUnitResult unit, Annotation annotation) {
    _safety.check(unit, annotation, syntax: annotation);
    return _value(
      _Visitor(
        this,
        unit.libraryElement as internal.LibraryElementImpl,
      ).evaluateConstant(annotation.expression),
      unit,
      annotation,
    );
  }

  internal.Constant? _variable(VariableElement variable) {
    variable = variable.baseElement as VariableElement;
    if (_values.containsKey(variable)) return _values[variable];
    if (!_active.add(variable)) {
      throw UnsupportedError('Cyclic constant dependency: ${variable.name}');
    }
    try {
      final element = variable as internal.VariableElementImpl;
      final initializer = element.constantInitializer2;
      final internal.Constant? result;
      if (initializer != null) {
        result = _Visitor(this, element.library!).evaluateConstant(
          initializer,
          implicitCastType:
              element.isConst || element is internal.FormalParameterElementImpl
              ? element.type
              : null,
        );
      } else if (variable case SuperFormalParameterElement(
        hasDefaultValue: true,
        :final superConstructorParameter,
      )) {
        result = _variable(superConstructorParameter!);
      } else {
        result = element.evaluationResult;
      }
      if (element is internal.FieldElementImpl &&
          element.isEnumConstant &&
          result is internal.DartObjectImpl) {
        final owner = element.enclosingElement as internal.EnumElementImpl;
        result.updateEnumConstant(
          index: owner.constants.indexOf(element),
          name: element.name!,
        );
      }
      return _values[variable] = result;
    } finally {
      _active.remove(variable);
    }
  }

  DartObject? _value(
    internal.Constant? result,
    ResolvedUnitResult unit,
    AstNode site,
  ) {
    if (result == null || result is internal.DartObjectImpl) {
      return result as DartObject?;
    }
    final location = unit.lineInfo.getLocation(site.offset);
    throw UnsupportedError(
      '${unit.uri}:${location.lineNumber}:${location.columnNumber}: '
      'constant evaluation did not produce a valid value',
    );
  }
}

final class _Visitor(
  final ConstantEvaluation constants,
  final internal.LibraryElementImpl library,
) extends internal.ConstantVisitor {
  this
    : super(
        internal.ConstantEvaluationEngine(
          declaredVariables: library.session.declaredVariables,
          configuration: internal.ConstantEvaluationConfiguration(),
        ),
        library,
        DiagnosticReporter(
          RecordingDiagnosticListener(),
          library.firstFragment.source,
        ),
      );

  internal.Constant? _reference(Element? element) {
    if (element is PropertyAccessorElement) element = element.variable;
    if (element is! VariableElement || !element.isConst) return null;
    return constants._variable(element) ??
        (throw UnsupportedError('Missing constant value: ${element.name}'));
  }

  @override
  internal.Constant visitUnqualifiedNameExpression(
    internal.UnqualifiedNameExpressionImpl node,
  ) =>
      _reference(node.resolution?.element) ??
      super.visitUnqualifiedNameExpression(node);

  @override
  internal.Constant visitDotShorthandNameExpression(
    internal.DotShorthandNameExpressionImpl node,
  ) =>
      _reference(node.resolution?.element) ??
      super.visitDotShorthandNameExpression(node);

  @override
  internal.Constant visitImportPrefixedNameExpression(
    internal.ImportPrefixedNameExpressionImpl node,
  ) => switch (node.importPrefix.element) {
    internal.PrefixElementImpl(isDeferred: true) =>
      super.visitImportPrefixedNameExpression(node),
    _ =>
      _reference(node.resolution?.element) ??
          super.visitImportPrefixedNameExpression(node),
  };

  @override
  internal.Constant visitReceiverPropertyExtraction(
    internal.ReceiverPropertyExtractionImpl node,
  ) {
    if (node.receiver case internal.StaticQualifierImpl(:final importPrefix)) {
      if (importPrefix?.element case internal.PrefixElementImpl(
        isDeferred: true,
      )) {
        return super.visitReceiverPropertyExtraction(node);
      }
      if (_reference(node.resolution?.element) case final value?) return value;
    }
    return super.visitReceiverPropertyExtraction(node);
  }

  @override
  internal.Constant visitBinaryOperatorInvocation(
    BinaryOperatorInvocation node,
  ) {
    final operator = node.operator.type;
    if (!const {
          TokenType.EQ_EQ,
          TokenType.BANG_EQ,
          TokenType.LT,
          TokenType.LT_EQ,
          TokenType.GT,
          TokenType.GT_EQ,
        }.contains(operator) ||
        node.element?.enclosingElement is ExtensionElement ||
        node.element?.enclosingElement is ExtensionTypeElement) {
      return super.visitBinaryOperatorInvocation(node);
    }
    final left = evaluateConstant(node.leftOperand);
    if (left is! internal.DartObjectImpl) return left;
    final right = evaluateConstant(node.rightOperand);
    if (right is! internal.DartObjectImpl) return right;
    final mixed = switch ((left.state, right.state)) {
      (
        internal.IntState(value: final i?),
        internal.DoubleState(value: final d?),
      ) =>
        (i, d, false),
      (
        internal.DoubleState(value: final d?),
        internal.IntState(value: final i?),
      ) =>
        (i, d, true),
      _ => null,
    };
    if (mixed case (final integer, final floating, final reversed)) {
      int? order;
      if (!floating.isNaN) {
        order = integer == 0 && floating == 0 ? 0 : integer.compareTo(floating);
        if (reversed) order = -order;
      }
      final value = switch (operator) {
        TokenType.EQ_EQ => order == 0,
        TokenType.BANG_EQ => order != 0,
        TokenType.LT => order != null && order < 0,
        TokenType.LT_EQ => order != null && order <= 0,
        TokenType.GT => order != null && order > 0,
        _ => order != null && order >= 0,
      };
      return internal.DartObjectImpl(
        typeSystem,
        library.typeProvider.boolType,
        internal.BoolState.from(value),
      );
    }
    final computer = internal.DartObjectComputer(
      typeSystem,
      library.featureSet,
    );
    return switch (operator) {
      TokenType.EQ_EQ => computer.equalEqual(node, left, right),
      TokenType.BANG_EQ => computer.notEqual(node, left, right),
      TokenType.LT => computer.lessThan(node, left, right),
      TokenType.LT_EQ => computer.lessThanOrEqual(node, left, right),
      TokenType.GT => computer.greaterThan(node, left, right),
      _ => computer.greaterThanOrEqual(node, left, right),
    };
  }
}
