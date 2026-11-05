import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/extension_types.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_types');
  });
  test('erased members and construction match SDK values and effects', () {
    for (final (name, function) in <(String, int Function(int))>[
      ('shorthand', sdk.shorthand),
      ('dynamicRepresentation', sdk.dynamicRepresentation),
      ('genericContext', sdk.genericContext),
      ('basic', sdk.basic),
      ('captures', sdk.captures),
      ('updates', sdk.updates),
      ('statics', sdk.statics),
      ('record', sdk.record),
      ('functions', sdk.functions),
      ('nested', sdk.nested),
      ('constructors', sdk.constructors),
      ('cascades', sdk.cascades),
    ]) {
      for (final seed in [0, 3, 7]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    }
    for (final seed in <int?>[null, 0, 3]) {
      fixture.compare('nullable', [seed], () => sdk.nullable(seed));
    }
    for (final value in <int?>[null, 2]) {
      fixture.compare('optionalNullAware', [
        value,
      ], () => sdk.optionalNullAware(value));
    }
    for (final absent in [true, false]) {
      fixture.compare('nullAware', [absent], () => sdk.nullAware(absent));
    }
    fixture.compare('identity', [3], () => sdk.identity(3));
    fixture.compare('constants', [], sdk.constants);
    fixture.compare('moreConstants', [], sdk.moreConstants);
    fixture.compare('constructorIdentity', [], sdk.constructorIdentity);
    fixture.compare('aliasIdentity', [], sdk.aliasIdentity);
    fixture.compare('typeValues', [], sdk.typeValues);
    fixture.compare('nestedTypes', [], sdk.nestedTypes);
    for (final value in <Object?>[null, 2, 'bad']) {
      fixture.compare('checks', [value], () => sdk.checks(value));
      fixture.compare('casts', [value], () => sdk.casts(value));
      fixture.compare('checkedConstruction', [
        value,
      ], () => sdk.checkedConstruction(value));
      fixture.compare('patterns', [value], () => sdk.patterns(value));
    }
  });
  test(
    'extension types do not allocate nominal storage or virtual members',
    () {
      expect(fixture.program.classes, isEmpty);
      final operations = fixture.program.functions
          .expand((f) => f.blocks)
          .expand((b) => b.instructions);
      expect(operations.whereType<Construct>(), isEmpty);
      expect(operations.whereType<LoadField>(), isEmpty);
      expect(
        operations.whereType<InstanceCall>().where(
          (c) => c.member.name.startsWith('<extension-type:'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'cross-library extension types require registered declarations',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-extension-type-imports-',
      );
      try {
        final other = File('${directory.path}/other.dart')
          ..writeAsStringSync(
            'extension type E(int value) { int twice() => value * 2; }',
          );
        final entry = File('${directory.path}/entry.dart')
          ..writeAsStringSync(
            "import 'other.dart' as other; other.E keep(other.E value) => value; int run() => keep(other.E(3)).twice();",
          );
        await expectLater(
          CheckedLibraries.read([entry.path], Lowering.lower),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.toString(),
              'reason',
              contains('unregistered extension type'),
            ),
          ),
        );
        final program = await CheckedLibraries.read([
          entry.path,
          other.path,
        ], Lowering.lower);
        final run = program.functions.singleWhere(
          (f) => f.target.name == 'run',
        );
        expect(FixtureRunner(program, {}).run(run, []), 6);
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
  test('unsupported declarations fail before representation erasure', () async {
    final directory = Directory.systemTemp.createTempSync(
      'dartc-extension-types-',
    );
    try {
      for (final (source, reason) in [
        (
          'extension type E(int value) {} typedef Alias<T> = E; Object f() => Alias.new;',
          'extension type constructor alias',
        ),
        (
          'extension type E(int value) {} typedef Alias<T> = E; const f = Alias.new;',
          'extension type constructor alias',
        ),
        (
          'extension type E(int value) { factory E.zero(int value) = E; }',
          'extension type constructor shape',
        ),
      ]) {
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        await expectLater(
          CheckedLibraries.read([file.path], Lowering.lower),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.toString(),
              'reason',
              contains(reason),
            ),
          ),
        );
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
