/// Dart compilation unit, declaration, expression, statement, pattern and type parsing.
///
/// Parsing consumes an existing scan result without changing its tokens.
/// Syntax nodes retain the source snapshot; name resolution and type checking
/// belong to analysis. All entry points accept a [LanguageVersion], defaulting
/// to [LanguageVersion.current]. The caller selects it from the file and package
/// configuration; parsing does not interpret language-version comments.
///
/// {@example /example/parser.dart}
library;

export 'src/parser/parser.dart'
    show
        parseExpression,
        parseStatement,
        parseTypeAnnotation,
        parseFormalParameterList,
        parseFunctionBody,
        parseCompilationUnit,
        parsePattern,
        PatternContext,
        ParseResult;

export 'src/parser/language_version.dart';
