import 'source_text.dart';

class Diagnostic {
  final String message;
  final SourceText? source;
  // The original half-open UTF-16 range; a point diagnostic has start == end.
  final int start;
  final int end;
  final int exitCode;

  Diagnostic(
    this.message, {
    this.source,
    this.start = -1,
    this.end = -1,
    this.exitCode = 1,
  });

  String toString() => message;
}
