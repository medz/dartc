import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'conversions.dart';
import 'primary.dart';
import 'scope.dart';
import 'statement.dart';
import 'types.dart';

/// Translates constructors of extension types, which give the value that
/// objects of those are.
final class ExtensionConstructorTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
  final StatementTranslator _statements,
) {
  late final _conversions = Conversions(_scope, _builder);

  DartType get _type => _builder.returnType!;

  HirValue _converted(HirValue value) =>
      _conversions.coerce(value, valueType(_type)!);

  /// Translates the constructor that [node] declares in [owner].
  ///
  /// That is [owner] itself for one made of its name.
  void translate(ExtensionTypeElement owner, AstNode node) {
    final (:initializers, :body) = partsOf(node);
    final value = node is ConstructorDeclaration
        ? _converted(_initial(node, initializers))
        : _converted(_builder.read(_primary(owner)));
    if (body != null && body is! EmptyFunctionBody) {
      _builder
        ..setReceiver(value, null)
        ..thisType = owner.thisType
        ..fallback = () => value;
      _statements.body(body);
    } else {
      _builder.stay();
    }
    _builder.end(HirReturn(value));
  }

  static FormalParameterElement _primary(ExtensionTypeElement owner) =>
      owner.primaryConstructor.formalParameters.single;

  HirValue _initial(
    ConstructorDeclaration node,
    List<ConstructorInitializer> initializers,
  ) {
    final expressions = _statements.expressions;
    HirValue? value;
    for (final parameter in node.declaredFragment!.element.formalParameters) {
      if (parameter is FieldFormalParameterElement) {
        value = _builder.read(parameter);
      }
    }
    for (final initializer in initializers) {
      switch (initializer) {
        case ConstructorFieldInitializer(:final expression):
          value = expressions.valueTo(expression, _type);
        case RedirectingConstructorInvocation(:final element?):
          value = expressions.calls.create(
            initializer,
            element,
            expressions.calls.supplied(initializer.argumentList),
          );
        case AssertInitializer():
          _statements.assertions.check(initializer);
        case _:
          break;
      }
    }
    return value!;
  }
}
