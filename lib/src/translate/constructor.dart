import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'classes.dart';
import 'members.dart';
import 'scope.dart';
import 'statement.dart';

/// Whether [element] is a constructor that works on an object created before.
bool isInitializerElement(ExecutableElement element) =>
    element is ConstructorElement && !element.isFactory;

/// Whether the function of [element] takes an object first.
bool hasReceiver(ExecutableElement element) =>
    isInstanceMember(element) || isInitializerElement(element);

/// Translates generative constructors.
final class ConstructorTranslator(
  final ProgramScope _scope,
  final Declarations _declarations,
  final FunctionBuilder _builder,
  final StatementTranslator _statements,
) {
  /// Sets fields, then runs the superclass's constructor, then the body.
  void initializer(ConstructorElement element) {
    final class_ = element.enclosingElement as ClassElement;
    final node = _declarations[element]?.$2 as ConstructorDeclaration?;
    if (element.isExternal) {
      throw _declarations.unsupported(element, 'external constructors');
    }
    final initializers = node?.initializers ?? const <ConstructorInitializer>[];
    for (final redirect
        in initializers.whereType<RedirectingConstructorInvocation>()) {
      _run(redirect.element!, redirect.argumentList, element);
      return;
    }
    _setFields(class_);
    for (final parameter in element.formalParameters) {
      if (parameter case FieldFormalParameterElement(:final field?)) {
        _store(field, _builder.read(parameter));
      }
    }
    SuperConstructorInvocation? explicit;
    for (final initializer in initializers) {
      switch (initializer) {
        case ConstructorFieldInitializer(
          fieldName: SimpleIdentifier(element: final FieldElement field),
        ):
          final type = _scope.fieldOf(field).type;
          _store(
            field,
            _statements.expressions.valueAs(initializer.expression, type),
          );
        case SuperConstructorInvocation():
          explicit = initializer;
        case AssertInitializer():
          break;
        default:
          throw _builder.unit.unsupported(initializer, 'this initializer');
      }
    }
    final parent = explicit?.element ?? element.superConstructor;
    if (parent != null && !parent.library.isInSdk) {
      _run(parent, explicit?.argumentList, element);
    }
    if (node != null && node.body is! EmptyFunctionBody) {
      _statements.body(node.body);
    }
  }

  /// Evaluates the initializers that fields are declared with.
  void _setFields(ClassElement class_) {
    for (final field in ClassTable.instanceFields(class_)) {
      final declaration = _declarations[field]!.$2 as VariableDeclaration;
      final initializer = declaration.initializer;
      if (initializer == null) continue;
      final type = _scope.fieldOf(field).type;
      _store(field, _statements.expressions.valueAs(initializer, type));
    }
  }

  void _store(FieldElement field, HirValue value) =>
      _builder.add(HirStore(_scope.fieldOf(field), _builder.receiver!, value));

  /// Runs constructor [target] on the same object, passing on the super
  /// parameters of [element].
  void _run(
    ConstructorElement target,
    ArgumentList? arguments,
    ConstructorElement element,
  ) {
    final supplied = arguments == null
        ? <FormalParameterElement, HirValue>{}
        : _statements.expressions.calls.supplied(arguments);
    for (final parameter in element.formalParameters) {
      if (parameter case SuperFormalParameterElement(
        :final superConstructorParameter?,
      )) {
        supplied[superConstructorParameter] = _builder.read(parameter);
      }
    }
    _builder.add(
      HirCall(_scope.initializerOf(target), [
        _builder.receiver!,
        ..._statements.expressions.calls.ordered(target, supplied),
      ]),
    );
  }
}
