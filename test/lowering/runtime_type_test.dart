import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/runtime_type.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async => fixture = await FixtureComparison.load('runtime_type'));

  for (final (name, expected) in [
    ('staticRuntimeTypes', sdk.staticRuntimeTypes),
    ('shapedRuntimeTypes', sdk.shapedRuntimeTypes),
    ('overriddenRuntimeType', sdk.overriddenRuntimeType),
    ('runtimeTypeWildcard', sdk.runtimeTypeWildcard),
  ]) {
    test('$name matches the Dart SDK', () {
      fixture.compare(name, [], expected);
    });
  }

  test('object patterns share cached runtimeType getter results', () {
    for (final overridden in [false, true]) {
      fixture.compare('runtimeTypePattern', [
        overridden,
      ], () => sdk.runtimeTypePattern(overridden));
    }
  });

  for (final name in ['setRuntimeType', 'mapRuntimeType', 'errorRuntimeType']) {
    test('$name retains the unsupported concrete SDK type boundary', () {
      final entry = fixture.program.functions.singleWhere(
        (function) => function.target.name == name,
      );
      expect(
        () => FixtureRunner(fixture.program, {}).run(entry, []),
        throwsUnsupportedError,
      );
    });
  }

  test('super.runtimeType is not lowered as virtual dispatch', () async {
    final directory = Directory.systemTemp.createTempSync(
      'dartc-runtime-type-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync('''
class C {
  @override
  Type get runtimeType => int;
  Type original() => super.runtimeType;
}
''');
    await expectLater(
      CheckedLibraries.read([file.path], Lowering.lower),
      throwsUnsupportedError,
    );
  });
}
