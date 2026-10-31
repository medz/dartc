import 'package:dartc/project.dart';
import 'package:test/test.dart';

void main() {
  test('resolves logical URIs without merging file-system aliases', () {
    for (final (base, reference, expected) in [
      ('file:///app/lib/a.dart', '../b.dart', 'file:///app/b.dart'),
      ('package:p/src/a.dart', '../b.dart', 'package:p/b.dart'),
      ('package:p/a.dart', '../q/b.dart', 'package:p/q/b.dart'),
      ('package:p/a.dart', '/b.dart', 'package:p/b.dart'),
      ('package:p/a.dart', 'a//b.dart', 'package:p/a//b.dart'),
      ('package:p/a.dart', 'a%2Fb.dart', 'package:p/a%2Fb.dart'),
      ('dart:core', 'bool.dart', 'dart:core/bool.dart'),
      ('dart:core/src/a.dart', '../b.dart', 'dart:core/b.dart'),
      ('memory:/app/main.dart', './a.dart', 'memory:/app/a.dart'),
      ('package:p/a.dart', 'package:q/b.dart', 'package:q/b.dart'),
    ]) {
      expect(
        resolveSourceUri(Uri.parse(reference), from: Uri.parse(base)),
        Uri.parse(expected),
      );
    }
    expect(
      resolveSourceUri(Uri.parse('file:///app/a/../b.dart')),
      Uri.parse('file:///app/b.dart'),
    );
  });

  test('rejects malformed URIs and paths escaping a package', () {
    for (final value in [
      'package://p/b.dart',
      'package:p',
      'package:p/%2e%2e/b.dart',
      'a.dart?x',
      'a.dart#x',
    ]) {
      expect(
        () => resolveSourceUri(
          Uri.parse(value),
          from: Uri.parse('package:p/a.dart'),
        ),
        throwsFormatException,
        reason: value,
      );
    }
    expect(
      () => resolveSourceUri(Uri.parse('relative.dart')),
      throwsFormatException,
    );
  });
}
