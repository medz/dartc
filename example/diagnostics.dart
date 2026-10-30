import 'package:dartc/diagnostics.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(
    Uri.parse('memory:example.dart'),
    'final item = 1;\nfinal item = 2;\n',
  );
  final diagnostic = Diagnostic(
    code: 'example.duplicate_name',
    severity: .error,
    message: "The name 'item' is already declared.",
    span: SourceSpan(source, 22, 26),
    notes: [
      DiagnosticNote(
        message: 'The first declaration is here.',
        span: SourceSpan(source, 6, 10),
      ),
    ],
  );

  final span = diagnostic.span!;
  final (:line, :column) = span.source.lineInfo.location(span.start);
  print(
    '${span.source.uri}:$line:$column: '
    '${diagnostic.severity.name}: ${diagnostic.message}',
  );
  for (final note in diagnostic.notes) {
    final (:line, :column) = note.span.source.lineInfo.location(
      note.span.start,
    );
    print('${note.span.source.uri}:$line:$column: ${note.message}');
  }
}
