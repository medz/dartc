import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test('unsupported special constants are not empty user instances', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-constant-');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final expression in ["const Duration(seconds: 1)"]) {
      final file = File('${directory.path}/entry.dart')
        ..writeAsStringSync('Object f() => $expression;');
      await expectLater(
        CheckedLibraries.read([file.path], Lowering.lower),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'source',
            contains('entry.dart:1:'),
          ),
        ),
        reason: expression,
      );
    }
  });
}
