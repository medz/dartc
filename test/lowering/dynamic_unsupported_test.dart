import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test('unimplemented dynamic dispatch is rejected at the operation', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-dynamic-');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final (expression, diagnostic) in [
      ('value.length', 'dynamic member dispatch'),
      ('value[0]', 'dynamic member dispatch'),
      ('value.foo()', 'dynamic member dispatch'),
      ('value()', 'dynamic function invocation'),
      ('value + 1', 'dynamic operator dispatch'),
      ('value == 1', 'dynamic operator dispatch'),
    ]) {
      final file = File('${directory.path}/entry.dart')
        ..writeAsStringSync('Object? f(dynamic value) => $expression;');
      await expectLater(
        CheckedLibraries.read([file.path], Lowering.lower),
        throwsA(
          isA<UnsupportedError>()
              .having((e) => e.message, 'operation', contains(diagnostic))
              .having((e) => e.message, 'source', contains('entry.dart:1:')),
        ),
        reason: expression,
      );
    }
  });
}
