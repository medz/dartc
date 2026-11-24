import 'package:analyzer/dart/ast/ast.dart';

/// What a constructor does besides taking parameters.
typedef ConstructorParts = ({
  List<ConstructorInitializer> initializers,
  FunctionBody? body,
});

/// The parts of the constructor that [node] declares.
///
/// That is a class, or something like it, for its primary constructor.
ConstructorParts partsOf(AstNode? node) {
  if (node case ConstructorDeclaration(:final initializers, :final body)) {
    return (initializers: initializers, body: body);
  }
  for (final member in _membersOf(node)) {
    if (member case PrimaryConstructorBody(:final initializers, :final body)) {
      return (initializers: initializers, body: body);
    }
  }
  return (initializers: const [], body: null);
}

List<ClassMember> _membersOf(AstNode? node) => switch (node) {
  ClassDeclaration(:final body) ||
  ExtensionTypeDeclaration(:final body) => body.members,
  EnumDeclaration(:final body) => body.members,
  _ => const [],
};

/// Whether [node] is a class, or something like it, with a primary
/// constructor.
bool hasPrimary(AstNode? node) => switch (node) {
  ClassDeclaration(:final namePart) ||
  EnumDeclaration(:final namePart) ||
  ExtensionTypeDeclaration(
    :final namePart,
  ) => namePart is PrimaryConstructorDeclaration,
  _ => false,
};
