import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/private_named/declarations.dart' as declarations;
import 'fixtures/private_named/entry.dart' as sdk;

void main() {
  late FixtureComparison comparison;
  setUpAll(() async {
    comparison = FixtureComparison(
      await CheckedLibraries.read([
        'test/lowering/fixtures/private_named/entry.dart',
        'test/lowering/fixtures/private_named/declarations.dart',
      ], Lowering.lower),
    );
  });

  for (final (name, reference) in [
    ('direct', sdk.direct),
    ('forwarded', sdk.forwarded),
    ('tearoffs', sdk.tearoffs),
    ('dynamicCalls', sdk.dynamicCalls),
    ('privateKey', sdk.privateKey),
    ('missingRequired', sdk.missingRequired),
    ('local', declarations.local),
  ]) {
    test('private field formals: $name agrees with SDK', () {
      comparison.compare(name, [], reference);
    });
  }

  for (final source in [
    'int function({int _value = 1}) => _value;',
    'class Box { final int _value; Box({this._value = 1}); } '
        'Box run() => Box(_value: 2);',
    'class Box { final int _value; Box({this._value = 1}); } '
        'class Child extends Box { Child({super._value}); }',
    '// @dart=3.11\nclass Box { final int _value; Box({this._value = 1}); }',
  ]) {
    test(
      'checked analysis rejects invalid private parameter: $source',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'dartc-private-named-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        await expectLater(
          CheckedLibraries.read([file.path], Lowering.lower),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }
}
