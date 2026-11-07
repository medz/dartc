import 'dart:io';

import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/type_values.dart' as sdk;

void main() {
  test('a source const cannot capture a reified type parameter', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-type-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync('Object f<T>() { const value = T; return value; }');
    await expectLater(
      CheckedLibraries.read([file.path], Lowering.lower),
      throwsFormatException,
    );
  });
  late FixtureComparison fixture;
  setUpAll(() async => fixture = await FixtureComparison.load('type_values'));
  for (final (name, expected) in [
    ('typeConstants', sdk.typeConstants),
    ('typeBoundaries', sdk.typeBoundaries),
    ('typeRuntime', sdk.typeRuntime),
    ('typeCollections', sdk.typeCollections),
    ('typeCheckCalls', sdk.typeCheckCalls),
    ('typeHashDispatch', sdk.typeHashDispatch),
  ]) {
    test('$name matches the Dart SDK', () {
      fixture.compare(name, [], expected);
    });
  }
}
