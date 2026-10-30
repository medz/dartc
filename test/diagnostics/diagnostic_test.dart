import 'package:dartc/diagnostics.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:example.dart');

  group('Diagnostic', () {
    test('can report an issue without a source location', () {
      final diagnostic = Diagnostic(
        code: 'example.source_not_found',
        severity: .error,
        message: 'Could not read the source.',
      );

      expect(diagnostic.span, isNull);
      expect(diagnostic.notes, isEmpty);
    });

    test('preserves locations across files and source snapshots', () {
      final previous = SourceFile(uri, 'first');
      final current = SourceFile(uri, 'second');
      final other = SourceFile(Uri.parse('memory:other.dart'), 'third');
      final primary = SourceSpan(current, current.length, current.length);
      final previousLocation = SourceSpan(previous, 0, previous.length);
      final otherLocation = SourceSpan(other, 0, other.length);
      final diagnostic = Diagnostic(
        code: 'example.changed_declaration',
        severity: .warning,
        message: 'The declaration has changed.',
        span: primary,
        notes: [
          DiagnosticNote(message: 'Previous version.', span: previousLocation),
          DiagnosticNote(message: 'Related declaration.', span: otherLocation),
        ],
      );

      expect(diagnostic.span, same(primary));
      expect(diagnostic.notes[0].span, same(previousLocation));
      expect(diagnostic.notes[1].span, same(otherLocation));
    });

    test('copies notes without sorting, deduplicating, or cloning them', () {
      final source = SourceFile(uri, 'abc');
      final first = DiagnosticNote(
        message: 'The later location is explained first.',
        span: SourceSpan(source, 2, 3),
      );
      final second = DiagnosticNote(
        message: 'The earlier location is explained second.',
        span: SourceSpan(source, 0, 1),
      );
      final notes = [first, second, first];
      final diagnostic = Diagnostic(
        code: 'example.related_locations',
        severity: .info,
        message: 'See the related locations.',
        notes: notes,
      );

      notes[0] = second;
      notes.clear();

      expect(diagnostic.notes, hasLength(3));
      expect(diagnostic.notes[0], same(first));
      expect(diagnostic.notes[1], same(second));
      expect(diagnostic.notes[2], same(first));
    });

    test('does not alias an initially empty notes list', () {
      final source = SourceFile(uri, '');
      final notes = <DiagnosticNote>[];
      final diagnostic = Diagnostic(
        code: 'example.no_context',
        severity: .info,
        message: 'No related locations.',
        notes: notes,
      );

      notes.add(
        DiagnosticNote(message: 'Added later.', span: SourceSpan(source, 0, 0)),
      );

      expect(diagnostic.notes, isEmpty);
    });

    test('does not allow callers to modify stored notes', () {
      final source = SourceFile(uri, '');
      final note = DiagnosticNote(
        message: 'An empty source.',
        span: SourceSpan(source, 0, 0),
      );
      final withoutNotes = Diagnostic(
        code: 'example.no_context',
        severity: .info,
        message: 'No related locations.',
      );
      final withNotes = Diagnostic(
        code: 'example.with_context',
        severity: .info,
        message: 'See the related location.',
        notes: [note],
      );

      for (final diagnostic in [withoutNotes, withNotes]) {
        expect(() => diagnostic.notes.add(note), throwsUnsupportedError);
        expect(() => diagnostic.notes.clear(), throwsUnsupportedError);
      }
      expect(() => withNotes.notes[0] = note, throwsUnsupportedError);
      expect(withoutNotes.notes, isEmpty);
      expect(withNotes.notes, [note]);
    });
  });
}
