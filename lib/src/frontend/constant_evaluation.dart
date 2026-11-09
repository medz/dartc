// The pinned analyzer evaluator consumes its canonical, experimental AST API.
// ignore_for_file: experimental_member_use

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart' show DartObject;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
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
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/member.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_algebra.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diagnostics;

import 'constant_safety.dart';

/// Checks and evaluates constants with exact mixed numeric comparisons.
final class ConstantEvaluation() {
  final _safety = ConstantSafety();
  final _values = <VariableElement, internal.Constant?>{};
  final _active = <VariableElement>{};

  /// Checks constant obligations in every declaration, including dead code.
  void check(ResolvedUnitResult unit) {
    final errors = unit.diagnostics.where((d) => d.severity == .error).toList();
    for (final error in errors) {
      if (!_evaluationErrors.contains(error.diagnosticCode)) {
        _fail(unit, error);
      }
    }
    unit.unit.accept2(_CheckConstants(this, unit, errors));
    for (final error in errors) {
      _fail(unit, error);
    }
  }

  // Only value-dependent errors can be discharged by successful evaluation.
  static final _evaluationErrors = {
    diagnostics.constEvalThrowsException,
    diagnostics.constEvalThrowsIdbze,
    diagnostics.constConstructorParamTypeMismatch,
    diagnostics.constConstructorFieldTypeMismatch,
    diagnostics.variableTypeMismatch,
  };

  static Never _fail(ResolvedUnitResult unit, Diagnostic error) =>
      throw FormatException(
        '${unit.uri}: ${error.message}',
        unit.content,
        error.offset,
      );

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
    final invalid = result as internal.InvalidConstant;
    final diagnostic =
        DiagnosticReporter(
          DiagnosticListener.nullListener,
          unit.libraryElement.firstFragment.source,
        ).atOffset(
          offset: site.offset,
          length: site.length,
          diagnosticCode: invalid.locatableDiagnostic.code,
          arguments: invalid.locatableDiagnostic.arguments,
          contextMessages: invalid.locatableDiagnostic.contextMessages.toList(),
        );
    throw FormatException(
      '${unit.uri}: ${diagnostic.message}',
      unit.content,
      site.offset,
    );
  }
}

final class _CheckConstants(
  final ConstantEvaluation constants,
  final ResolvedUnitResult unit,
  final List<Diagnostic> errors,
) extends UnifyingAstVisitor2<void> {
  late final _visitor = _Visitor(
    constants,
    unit.libraryElement as internal.LibraryElementImpl,
  );

  void _check(internal.Constant? value, AstNode site) {
    constants._value(value, unit, site);
    if (value case internal.DartObjectImpl(isUnknown: false)) {
      errors.removeWhere(
        (error) =>
            error.offset >= site.offset &&
            error.offset + error.length <= site.end,
      );
    }
  }

  void _expression(Expression expression) =>
      _check(_visitor.evaluateConstant(expression), expression);

  @override
  void visitNode(AstNode node) {
    switch (node) {
      case internal.VariableBindingImpl(
            declaredFragment: final fragment?,
            initializer2: final initializer?,
          )
          when fragment.isConst:
        _check(constants._variable(fragment.element), initializer);
      case internal.FormalParameterDefaultClauseImpl(:final value2):
        final parameter = node.parent2 as internal.FormalParameterImpl;
        _check(
          constants._variable(parameter.declaredFragment!.element),
          value2,
        );
      case EnumConstantDeclaration2(declaredFragment: final fragment?):
        _check(constants._variable(fragment.element), node);
      case Annotation(:final expression):
        _expression(expression);
      case ConstructorInvocation(isConst: true) ||
          DotShorthandConstructorInvocation2(isConst: true) ||
          ListLiteral(isConst: true) ||
          SetOrMapLiteral(isConst: true) ||
          RecordLiteral(isConst: true):
        _expression(node as Expression);
      case ConstantPattern(:final expression2):
        _expression(expression2);
      case RelationalPattern(:final operand2):
        _expression(operand2);
      case MapPatternEntry(:final key2):
        _expression(key2);
    }
    super.visitNode(node);
  }
}

final class _Visitor(
  final ConstantEvaluation constants,
  final internal.LibraryElementImpl library, {
  Map<FormalParameterElement, internal.DartObjectImpl>? parameters,
  internal.InterfaceTypeImpl? owner,
}) extends internal.ConstantVisitor {
  this
    : super(
        _Engine(constants, library),
        library,
        DiagnosticReporter(
          RecordingDiagnosticListener(),
          library.firstFragment.source,
        ),
        lexicalEnvironment: parameters,
        lexicalTypeEnvironment: owner == null
            ? null
            : {
                for (final (i, p) in owner.element.typeParameters.indexed)
                  p: owner.typeArguments[i],
              },
        substitution: owner == null
            ? null
            : internal.Substitution.fromInterfaceType(owner),
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
    final a = left.toIntValue() ?? left.toDoubleValue();
    final b = right.toIntValue() ?? right.toDoubleValue();
    if (a != null && b != null) {
      int? order;
      if (!a.isNaN && !b.isNaN) {
        order = a == 0 && b == 0 ? 0 : a.compareTo(b);
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

final class _Invalid(final internal.InvalidConstant value) implements Exception;

/// Supplies the same expression evaluator to every constructor environment.
final class _Engine(
  final ConstantEvaluation constants,
  internal.LibraryElementImpl library,
) extends internal.ConstantEvaluationEngine {
  this
    : super(
        declaredVariables: library.session.declaredVariables,
        configuration: internal.ConstantEvaluationConfiguration(),
      );

  @override
  internal.Constant evaluateAndFormatErrorsInConstructorCall(
    internal.LibraryElementImpl library,
    AstNode node,
    List<internal.TypeImpl>? typeArguments,
    List<Argument> arguments,
    internal.InternalConstructorElement constructor,
    internal.ConstantVisitor constantVisitor, {
    internal.ConstructorInvocationDataImpl? invocation,
  }) {
    var destination = constructor;
    final visited = <ConstructorElement>{};
    while (visited.add(destination.baseElement)) {
      final redirect = internal
          .ConstantEvaluationEngine.getConstRedirectedConstructor(destination);
      if (redirect == null) break;
      destination = redirect;
    }
    // External core factories retain analyzer's environment and Symbol handling.
    if (destination.isFactory || destination.isExternal) {
      return super.evaluateAndFormatErrorsInConstructorCall(
        library,
        node,
        typeArguments,
        arguments,
        constructor,
        constantVisitor,
        invocation: invocation,
      );
    }
    try {
      return _invoke(constructor, arguments, constantVisitor, node, invocation);
    } on _Invalid catch (error) {
      return internal.InvalidConstant.copyWithEntity(
        other: error.value,
        entity: node,
      );
    }
  }

  internal.DartObjectImpl _invoke(
    internal.InternalConstructorElement constructor,
    List<Argument> arguments,
    internal.ConstantVisitor caller,
    AstNode site,
    internal.ConstructorInvocationDataImpl? invocation, {
    Map<FormalParameterElement, internal.DartObjectImpl> implicit = const {},
  }) {
    final supplied = <FormalParameterElement, internal.DartObjectImpl>{
      ...implicit,
    };
    final positional = constructor.formalParameters.where(
      (p) => p.isPositional,
    );
    var index = 0;
    for (final argument in arguments) {
      final parameter = argument is NamedArgument
          ? constructor.formalParameters.firstWhere(
              (p) => p.isNamed && p.name == argument.name.lexeme,
            )
          : positional.elementAt(index++);
      supplied[parameter.baseElement] = _value(
        caller.evaluateConstant(argument),
      );
    }
    final call = internal.ConstructorInvocationDataImpl(
      constructor,
      [
        for (final p in constructor.formalParameters)
          if (p.isPositional) ?supplied[p.baseElement],
      ],
      {
        for (final p in constructor.formalParameters)
          if (p.isNamed && supplied.containsKey(p.baseElement))
            p.name!: supplied[p.baseElement]!,
      },
    );
    invocation ??= call;
    final seen = <ConstructorElement>{};
    while (true) {
      if (!constructor.isConst ||
          !constructor.baseElement.isCycleFree ||
          !seen.add(constructor.baseElement)) {
        _fail(site);
      }
      final redirect = internal
          .ConstantEvaluationEngine.getConstRedirectedConstructor(constructor);
      if (redirect == null) break;
      for (final p in constructor.formalParameters) {
        if (supplied[p.baseElement] case final value?) {
          _check(value, p.type, constructor.library, site);
        }
      }
      constructor = redirect;
      supplied.clear();
      var position = 0;
      for (final p in constructor.formalParameters) {
        final value = p.isNamed
            ? call.namedArguments[p.name]
            : position < call.positionalArguments.length
            ? call.positionalArguments[position++]
            : null;
        if (value != null) supplied[p.baseElement] = value;
      }
    }

    final type = constructor.returnType;
    final substitution = internal.Substitution.fromInterfaceType(type);
    final parameters = <FormalParameterElement, internal.DartObjectImpl>{};
    final fields = <String, internal.DartObjectImpl>{};
    for (final p in constructor.formalParameters) {
      if (!supplied.containsKey(p.baseElement) && !p.isOptional) _fail(site);
      final value =
          supplied[p.baseElement] ??
          _value(
            constants._variable(p) ??
                internal.DartObjectImpl(
                  constructor.library.typeSystem,
                  constructor.library.typeProvider.nullType,
                  internal.NullState.NULL_STATE,
                ),
          );
      _check(value, p.type, constructor.library, site);
      parameters[p.baseElement] = value;
      if (p case FieldFormalParameterElement(:final field?)) {
        _check(
          value,
          field.type as internal.TypeImpl,
          constructor.library,
          site,
        );
        fields[field.name!] = value;
      }
    }
    final evaluator = _Visitor(
      constants,
      constructor.library,
      parameters: parameters,
      owner: type,
    );
    final initializers = constructor.baseElement.constantInitializers;
    if (!initializers.any((i) => i is RedirectingConstructorInvocation)) {
      for (final field in constructor.baseElement.enclosingElement.fields) {
        if (!field.isStatic && field.constantInitializer2 != null) {
          final value = _value(
            evaluator.evaluateConstant(field.constantInitializer2!),
          );
          _check(
            value,
            substitution.substituteType(field.type),
            constructor.library,
            site,
          );
          fields[field.name!] = value;
        }
      }
    }
    SuperConstructorInvocation? superCall;
    for (final initializer in initializers) {
      switch (initializer) {
        case ConstructorFieldInitializer():
          final value = _value(
            evaluator.evaluateConstant(initializer.expression2),
          );
          final name = initializer.fieldName2.lexeme;
          _check(
            value,
            type.getGetter(name)!.returnType,
            constructor.library,
            site,
          );
          fields[name] = value;
        case AssertInitializer():
          final condition = _value(
            evaluator.evaluateConstant(initializer.condition2),
          );
          if (condition.toBoolValue() != true) {
            final message = initializer.message2 == null
                ? null
                : _value(evaluator.evaluateConstant(initializer.message2!))
                      .toStringValue();
            throw _Invalid(
              internal.InvalidConstant.forEntity(
                entity: site,
                locatableDiagnostic: message == null
                    ? diagnostics.constEvalAssertionFailure
                    : diagnostics.constEvalAssertionFailureWithMessage
                          .withArguments(message: message),
                isRuntimeException: true,
              ),
            );
          }
        case RedirectingConstructorInvocation():
          final redirect = internal.SubstitutedConstructorElementImpl.from2(
            (initializer.element! as internal.InternalConstructorElement)
                .baseElement,
            type,
          );
          return _invoke(
            redirect,
            initializer.argumentList.arguments2,
            evaluator,
            site,
            invocation,
          );
        case SuperConstructorInvocation():
          superCall = initializer;
      }
    }
    final superclass = type.superclass;
    // Enum index/name are supplied by variable evaluation, not a source constructor.
    if (superclass != null &&
        !superclass.isDartCoreObject &&
        !superclass.isDartCoreEnum) {
      final parent = superclass.lookUpConstructor(
        superCall?.constructorSelector?.name2.lexeme,
        constructor.library,
      );
      if (parent == null) _fail(site);
      fields[internal.GenericState.SUPERCLASS_FIELD] = _invoke(
        parent,
        superCall?.argumentList.arguments2 ?? const [],
        evaluator,
        site,
        null,
        implicit: {
          for (final p in constructor.formalParameters)
            if (p case SuperFormalParameterElement(
              superConstructorParameter: final parent?,
            ))
              parent.baseElement: parameters[p.baseElement]!,
        },
      );
    }
    if (type.element case ExtensionTypeElement(:final representation)) {
      final value = fields[representation.name]!;
      return internal.DartObjectImpl.withExtensionType(
        typeSystem: constructor.library.typeSystem,
        type: value.type,
        typeNotExtensionTypeErased: type,
        state: value.state,
        variable: value.variable,
      );
    }
    return internal.DartObjectImpl(
      constructor.library.typeSystem,
      type,
      internal.GenericState(fields, invocation: invocation),
    );
  }

  internal.DartObjectImpl _value(internal.Constant value) => switch (value) {
    internal.DartObjectImpl() => value,
    internal.InvalidConstant() => throw _Invalid(value),
  };

  void _check(
    internal.DartObjectImpl value,
    internal.TypeImpl type,
    internal.LibraryElementImpl library,
    AstNode site,
  ) {
    if (!library.typeSystem.isSubtypeOf(
      value.type,
      type.extensionTypeErasure,
    )) {
      _fail(site);
    }
  }

  Never _fail(AstNode site) => throw _Invalid(
    internal.InvalidConstant.forEntity(
      entity: site,
      locatableDiagnostic: diagnostics.constEvalThrowsException,
    ),
  );
}
