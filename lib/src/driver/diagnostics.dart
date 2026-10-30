import '../diagnostic.dart';

String formatDiagnostic(Diagnostic diagnostic) {
  final source = diagnostic.source;
  if (source == null) return 'dartc: ${diagnostic.message}\n';
  final text = source.text;
  final offset = diagnostic.start;
  var line = 1;
  var lineStart = 0;
  var at = 0;
  while (at < offset) {
    final unit = text.codeUnitAt(at++);
    if (unit == 13) {
      if (at < text.length && text.codeUnitAt(at) == 10) {
        if (at == offset) break;
        at++;
      }
    } else if (unit != 10) {
      continue;
    }
    line++;
    lineStart = at;
  }
  var lineEnd = lineStart;
  while (lineEnd < text.length &&
      text.codeUnitAt(lineEnd) != 10 &&
      text.codeUnitAt(lineEnd) != 13)
    lineEnd++;
  final column = offset - lineStart + 1;
  return '${source.path}:$line:$column: ${diagnostic.message}\n'
      '${text.substring(lineStart, lineEnd)}\n';
}
