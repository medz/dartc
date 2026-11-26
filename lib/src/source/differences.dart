import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
// Only this substitutes the type arguments of an extension.
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_algebra.dart' show Substitution;

/// The errors of [unit] that only the official compiler finds, with where they
/// are.
List<(int, String)> errorsMissedIn(CompilationUnit unit) {
  final found = _Missed();
  unit.accept(found);
  return found.errors;
}

final class _Missed() extends RecursiveAstVisitor<void> {
  final errors = <(int, String)>[];

  @override
  void visitFunctionReference(FunctionReference node) {
    if (node.typeArguments != null && _canBeShortened(node.function)) {
      errors.add((node.offset, 'What gets type arguments here can be null.'));
    }
    super.visitFunctionReference(node);
  }

  /// Whether [node] is in a chain that a `?.` can cut short. The official
  /// compiler ignores `this?.`, which is never null.
  static bool _canBeShortened(Expression node) {
    bool isShort(bool isNullAware, Expression? target) =>
        isNullAware && target is! ThisExpression ||
        target != null && _canBeShortened(target);
    return switch (node) {
      PropertyAccess(:final isNullAware, :final target) => isShort(
        isNullAware,
        target,
      ),
      MethodInvocation(:final isNullAware, :final target) => isShort(
        isNullAware,
        target,
      ),
      IndexExpression(:final isNullAware, :final target) => isShort(
        isNullAware,
        target,
      ),
      FunctionExpressionInvocation(:final function) => _canBeShortened(
        function,
      ),
      _ => false,
    };
  }

  @override
  void visitTypeLiteral(TypeLiteral node) {
    if (node.type
        case NamedType(
          importPrefix: ImportPrefixReference(
            element: PrefixElement(:final imports),
          ),
          typeArguments: _?,
        )
        when imports.any((i) => i.prefix?.isDeferred ?? false)) {
      errors.add((
        node.offset,
        'A type of a deferred library has no type arguments here.',
      ));
    }
    super.visitTypeLiteral(node);
  }
}

/// Whether the official compiler accepts what [error] of [unit] is about.
bool isAccepted(Diagnostic error, CompilationUnit unit) {
  AstNode? node() =>
      unit.nodeCovering(offset: error.offset, length: error.length);
  return switch (error.diagnosticCode.lowerCaseName) {
    'unchecked_use_of_nullable_value' => _isOfExtensionType(node()),
    'address_receiver' => _isOwnField(node()),
    'argument_type_not_assignable' ||
    'invalid_assignment' => _fitsNamedExtension(node()),
    _ => false,
  };
}

/// The type of [node] if it uses an operator of an extension that is named
/// with its type arguments, with those, and the library of the extension.
(DartType, LibraryElement)? _resultOfNamedExtension(Expression node) {
  if (node is! BinaryExpression) return null;
  final override = node.leftOperand.unParenthesized;
  final operator = node.element;
  if (override is! ExtensionOverride || operator == null) return null;
  final types = override.typeArgumentTypes;
  if (types == null) return null;
  final extension = override.element;
  final result = Substitution.fromPairs2(
    extension.typeParameters,
    types,
  ).substituteType(operator.returnType);
  return (result, extension.library);
}

/// Whether [node] is the right operand of an operator of an extension that is
/// named with its type arguments, and fits the parameter with those. The
/// analyzer takes the parameter as it is declared.
bool _fitsNamedExtension(AstNode? node) {
  if (node is! Expression) return false;
  if (_resultOfNamedExtension(node.unParenthesized)
      case (final type, final library)?) {
    final target = switch (node.parent) {
      VariableDeclaration(:final declaredFragment?) =>
        declaredFragment.element.type,
      AssignmentExpression(:final writeType) => writeType,
      _ => null,
    };
    return target != null && library.typeSystem.isAssignableTo(type, target);
  }
  final parent = node.parent;
  if (parent is! BinaryExpression || parent.rightOperand != node) return false;
  final override = parent.leftOperand.unParenthesized;
  final operator = parent.element;
  if (override is! ExtensionOverride || operator == null) return false;
  final types = override.typeArgumentTypes;
  final extension = override.element;
  final given = node.staticType;
  if (types == null || given == null) return false;
  final parameter = Substitution.fromPairs2(
    extension.typeParameters,
    types,
  ).substituteType(operator.formalParameters.single.type);
  return extension.library.typeSystem.isAssignableTo(given, parameter);
}

/// Whether [node] is a member of an extension type, used on a value whose type
/// is a type parameter that extends this. The analyzer takes that for null.
bool _isOfExtensionType(AstNode? node) {
  final use = node is SimpleIdentifier ? node.parent : node;
  final (DartType? target, Element? element) = switch (use) {
    MethodInvocation(:final realTarget, :final methodName) => (
      realTarget?.staticType,
      methodName.element,
    ),
    PropertyAccess(:final realTarget, :final propertyName) => (
      realTarget.staticType,
      propertyName.element ?? _written(use),
    ),
    PrefixedIdentifier(:final prefix, :final identifier) => (
      prefix.staticType,
      identifier.element ?? _written(use),
    ),
    BinaryExpression(:final leftOperand, :final element) => (
      leftOperand.staticType,
      element,
    ),
    // What `+=` and `++` read has its type only here.
    AssignmentExpression(:final readType, :final element) => (
      readType,
      element,
    ),
    PrefixExpression(:final operand, :final readType, :final element) ||
    PostfixExpression(
      :final operand,
      :final readType,
      :final element,
    ) => (readType ?? operand.staticType, element),
    _ => (null, null),
  };
  return element?.enclosingElement is ExtensionTypeElement &&
      _extendsExtensionType(target);
}

Element? _written(AstNode place) => switch (place.parent) {
  CompoundAssignmentExpression(:final writeElement) => writeElement,
  _ => null,
};

bool _extendsExtensionType(DartType? type) {
  if (type is! TypeParameterType) return false;
  DartType found = type;
  while (found is TypeParameterType) {
    if (found.nullabilitySuffix != .none) return false;
    found = found.bound;
  }
  return found.nullabilitySuffix == .none &&
      found is InterfaceType &&
      found.element is ExtensionTypeElement;
}

/// Whether [node] is `address` of a field that its own struct or union uses
/// without `this`, or of a field in parentheses.
bool _isOwnField(AstNode? node) {
  final place = switch (node?.parent) {
    PrefixedIdentifier(:final prefix) => prefix,
    PropertyAccess(:final target?) => target.unParenthesized,
    _ => null,
  };
  final element = switch (place) {
    SimpleIdentifier(:final element) => element,
    PrefixedIdentifier(:final identifier) => identifier.element,
    PropertyAccess(:final propertyName) => propertyName.element,
    _ => null,
  };
  if (element is! GetterElement) return false;
  final variable = element.variable;
  return variable is FieldElement &&
      variable.isExternal &&
      !variable.isStatic &&
      _isNumber(variable.type) &&
      _isCompound(variable.enclosingElement);
}

bool _isNumber(DartType type) =>
    type.isDartCoreInt || type.isDartCoreDouble || type.isDartCoreBool;

/// Whether [element] is a struct or union.
bool _isCompound(Element? element) =>
    element is InterfaceElement &&
    element.allSupertypes.any(
      (type) =>
          '${type.element.library.uri}' == 'dart:ffi' &&
          const ['Struct', 'Union'].contains(type.element.name),
    );
