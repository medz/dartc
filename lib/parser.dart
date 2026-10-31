/// Dart expression, statement and type parsing with ranges and diagnostics.
///
/// Parsing consumes an existing scan result without changing its tokens.
/// Syntax nodes retain the source snapshot; name resolution and type checking
/// belong to analysis.
///
/// {@example /example/parser.dart}
library;

export 'src/parser/parser.dart'
    show parseExpression, parseStatement, parseTypeAnnotation, ParseResult;
