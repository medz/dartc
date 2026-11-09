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
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/member.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_algebra.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diagnostics;

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
