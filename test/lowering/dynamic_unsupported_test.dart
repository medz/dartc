import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';

void main() {
  test('unmodeled existing SDK members are not reported as missing', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-dynamic-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(
        "Object? f() { dynamic value = <int>[1, 2]; return value.join(','); }",
      );
    final program = await CheckedLibraries.read([file.path], Lowering.lower);
    final entry = program.functions.singleWhere((f) => f.target.name == 'f');
    expect(
      () => FixtureRunner(program, {}).run(entry, []),
      throwsUnsupportedError,
    );
  });
}
