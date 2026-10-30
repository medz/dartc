/// Dart tokens, comments, and lexical diagnostics.
///
/// Scanning preserves source text and UTF-16 offsets. Parsing, language-version
/// selection, and literal value conversion belong to callers.
///
/// {@example /example/scanner.dart}
library;

export 'src/scanner/scanner.dart' show scan, ScanResult;
export 'src/scanner/token.dart';
export 'src/scanner/token_kind.dart';
