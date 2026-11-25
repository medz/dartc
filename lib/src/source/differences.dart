import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

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
    final function = node.function;
    if (function is PropertyAccess && function.isNullAware) {
      errors.add((node.offset, 'What gets type arguments here can be null.'));
    }
    super.visitFunctionReference(node);
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
    _ => false,
  };
}

/// Whether [node] is a member of an extension type, used on a value whose type
/// is a type parameter that extends this. The analyzer takes that for null.
bool _isOfExtensionType(AstNode? node) {
  final use = node is SimpleIdentifier ? node.parent : node;
  final (Expression? target, Element? element) = switch (use) {
    MethodInvocation(:final realTarget, :final methodName) => (
      realTarget,
      methodName.element,
    ),
    PropertyAccess(:final realTarget, :final propertyName) => (
      realTarget,
      propertyName.element ?? _written(use),
    ),
    PrefixedIdentifier(:final prefix, :final identifier) => (
      prefix,
      identifier.element ?? _written(use),
    ),
    BinaryExpression(:final leftOperand, :final element) => (
      leftOperand,
      element,
    ),
    _ => (null, null),
  };
  return element?.enclosingElement is ExtensionTypeElement &&
      _extendsExtensionType(target?.staticType);
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
  return variable is FieldElement && variable.isExternal && !variable.isStatic;
}
