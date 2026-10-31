part of 'parser.dart';

extension on _Parser {
  bool before(int major, int minor) =>
      languageVersion.major < major ||
      languageVersion.major == major && languageVersion.minor < minor;

  ParseResult<T> finishResult<T extends AstNode>(T node) {
    if (before(2, 12) ||
        languageVersion.major == 2 && languageVersion.minor > 19 ||
        languageVersion.minor < 0 ||
        languageVersion.compareTo(LanguageVersion.current) > 0) {
      error(
        'unsupported_language_version',
        'Supported language versions are 2.12 through ${LanguageVersion.current}.',
        Token(.invalid, source, 0, 0),
      );
    } else if (languageVersion != LanguageVersion.current) {
      checkLanguageFeatures(node);
    }
    return ParseResult._(node, diagnostics);
  }

  void requireFeature(AstNode node, int major, int minor, String feature) {
    if (!before(major, minor)) return;
    error(
      'language_feature_disabled',
      '$feature requires language version $major.$minor or later.',
      Token(.invalid, source, node.start, node.end),
    );
  }

  void checkLanguageFeatures(AstNode root) {
    // The call target distinguishes a generic named constructor invocation from
    // a tear-off without binding its unresolved names.
    final pending = <(AstNode, bool)>[(root, false)];
    while (pending.isNotEmpty) {
      final (node, called) = pending.removeLast();
      switch (node) {
        case TypeAliasDeclaration(:final type)
            when type is! FunctionTypeAnnotation:
          requireFeature(node, 2, 13, 'Non-function type aliases');
        case Annotation(typeArguments: final arguments?):
          requireFeature(arguments, 2, 14, 'Generic metadata');
        case BinaryExpression(op: .unsignedShiftRight) ||
            AssignmentExpression(op: .unsignedShiftRight) ||
            OperatorDeclaration(op: .unsignedShiftRight):
          requireFeature(node, 2, 14, 'Unsigned right shift');
        case TypeInstantiationExpression() when !called:
          requireFeature(node, 2, 15, 'Function and constructor tear-offs');
        case PropertyAccessExpression(:final property)
            when property.text == 'new':
          requireFeature(property, 2, 15, 'Constructor tear-offs');
        case FormalParameter(prefix: .superKeyword):
          requireFeature(node, 2, 17, 'Super parameters');
        case ArgumentList(:final arguments) when before(2, 17):
          var named = false;
          for (final argument in arguments) {
            if (argument.name != null) {
              named = true;
            } else if (named) {
              requireFeature(
                argument,
                2,
                17,
                'Positional arguments after named arguments',
              );
            }
          }
        case LibraryDirective(name: null):
          requireFeature(node, 2, 19, 'Unnamed libraries');
        case ClassDeclaration(
          :final modifiers,
          :final primaryParameters,
          :final isSemicolonBody,
        ):
          if (modifiers.any((m) => m != .abstractKeyword)) {
            requireFeature(node, 3, 0, 'Class modifiers');
          }
          if (primaryParameters != null || isSemicolonBody) {
            requireFeature(node, 3, 13, 'Primary constructors');
          }
        case ClassTypeAliasDeclaration(:final modifiers):
          if (modifiers.any((m) => m != .abstractKeyword)) {
            requireFeature(node, 3, 0, 'Class modifiers');
          }
        case MixinDeclaration(:final isBase, :final isSemicolonBody):
          if (isBase) requireFeature(node, 3, 0, 'Class modifiers');
          if (isSemicolonBody) {
            requireFeature(node, 3, 13, 'Empty declaration bodies');
          }
        case ExtensionDeclaration(:final isSemicolonBody):
          if (isSemicolonBody) {
            requireFeature(node, 3, 13, 'Empty declaration bodies');
          }
        case ExtensionTypeDeclaration():
          requireFeature(node, 3, 3, 'Extension types');
        case EnumDeclaration(
          :final typeParameters,
          :final withClause,
          :final implementsClause,
          :final hasMemberSeparator,
          :final primaryParameters,
          :final isSemicolonBody,
        ):
          if (typeParameters != null ||
              withClause != null ||
              implementsClause != null ||
              hasMemberSeparator) {
            requireFeature(node, 2, 17, 'Enhanced enums');
          }
          if (primaryParameters != null || isSemicolonBody) {
            requireFeature(node, 3, 13, 'Primary constructors');
          }
        case EnumConstantDeclaration(typeArguments: final arguments?):
          requireFeature(arguments, 2, 17, 'Enhanced enums');
        case EnumConstantDeclaration(arguments: final arguments?):
          requireFeature(arguments, 2, 17, 'Enhanced enums');
        case ConstructorDeclaration(keyword: .newKeyword):
          requireFeature(node, 3, 13, 'Abbreviated constructors');
        case PrimaryConstructorBody():
          requireFeature(node, 3, 13, 'Primary constructors');
        case RecordExpression() || RecordTypeAnnotation():
          requireFeature(node, 3, 0, 'Records');
        case SwitchExpression() ||
            PatternVariableDeclaration() ||
            PatternAssignmentExpression() ||
            PatternForInBinding():
          requireFeature(node, 3, 0, 'Patterns');
        case DartPattern()
            when node is! ConstantPattern && node is! IdentifierPattern:
          requireFeature(node, 3, 0, 'Patterns');
        case IfStatement(casePattern: final pattern?) ||
            IfElement(casePattern: final pattern?):
          requireFeature(pattern, 3, 0, 'If-case');
        case LiteralExpression(kind: .integer || .doubleLiteral):
          if (node.text.contains('_')) {
            requireFeature(node, 3, 6, 'Digit separators');
          }
        case NullAwareElement():
          requireFeature(node, 3, 8, 'Null-aware elements');
        case MapEntryElement(:final isNullAwareKey, :final isNullAwareValue):
          if (isNullAwareKey || isNullAwareValue) {
            requireFeature(node, 3, 8, 'Null-aware elements');
          }
        case DotShorthandExpression():
          requireFeature(node, 3, 10, 'Dot shorthands');
        default:
          break;
      }
      for (var i = node.childCount - 1; i >= 0; i--) {
        final child = node.childAt(i);
        final isTarget = switch (node) {
          InvocationExpression(:final callee) => identical(child, callee),
          PropertyAccessExpression(:final target) =>
            called && identical(child, target),
          _ => false,
        };
        pending.add((child, isTarget));
      }
    }
  }
}
