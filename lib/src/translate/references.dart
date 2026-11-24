import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'describe.dart';
import 'members.dart';
import 'scope.dart';
import 'types.dart';

/// Translates functions, constructors and types that are values.
final class ReferenceTranslator(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  Never _unsupported(AstNode node, String what) =>
      throw _builder.unit.unsupported(node, what);

  HirValue constructor(Expression node, ConstructorName name) {
    final element = name.element?.baseElement, type = node.staticType;
    if (element == null) {
      _unsupported(node, describe(node));
    }
    return _instantiate(node, element, type!);
  }

  /// A generic function with its type arguments, where [valueOf] evaluates
  /// the function if it is not known.
  HirValue function(
    FunctionReference node,
    HirValue Function(Expression node) valueOf,
  ) {
    final name = node.function;
    final element = switch (name) {
      SimpleIdentifier(:final element) => element,
      PrefixedIdentifier(identifier: SimpleIdentifier(:final element)) =>
        element,
      PropertyAccess(propertyName: SimpleIdentifier(:final element)) => element,
      ConstructorReference(:final constructorName) => constructorName.element,
      _ => null,
    };
    final isKnown =
        element is ConstructorElement ||
        element is ExecutableElement &&
            element is! PropertyAccessorElement &&
            _builder.typeOf(element) == null &&
            !isInstanceMember(element);
    if (isKnown) {
      element as ExecutableElement;
      return _instantiate(node, element.baseElement, node.staticType!);
    }
    final types = node.typeArgumentTypes ?? const [];
    final type = node.staticType;
    final list = _scope.typeList(_builder, types);
    if (types.isEmpty || type is! FunctionType || list == null) {
      _unsupported(node, describe(node));
    }
    final function = valueOf(name);
    return _scope.partial(_builder, function, (list, types.length), type);
  }

  HirValue _instantiate(
    Expression node,
    ExecutableElement element,
    DartType type,
  ) {
    if (type is! FunctionType || type.typeParameters.isNotEmpty) {
      _unsupported(node, 'generic functions as values');
    }
    final types = takesTypes(element) == null
        ? const <DartType>[]
        : typeArgumentsOf(element, type);
    return _scope.instantiate(_builder, element, types) ??
        _unsupported(node, describe(node));
  }

  /// The object that [type] is.
  HirValue type(AstNode node, DartType type) {
    if (_scope.typeObject(type) case final found?) {
      return _builder.add(HirStatic(found));
    }
    final own =
        _scope.typeValue(_builder, type) ??
        _unsupported(node, 'the type $type as a value');
    return _builder.call(HirCall(_scope.runtime('newType'), [own]))!;
  }

  /// The type that [element] is, where its name is an expression.
  static DartType? typeNamed(Element? element) => switch (element) {
    final TypeParameterElement element => element.instantiate(
      nullabilitySuffix: .none,
    ),
    _ => null,
  };
}
