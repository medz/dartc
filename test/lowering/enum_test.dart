import 'dart:io';

import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/enums.dart' as sdk;

void main() {
  group('enum SDK comparison', () {
    late FixtureComparison fixture;
    setUpAll(() async => fixture = await FixtureComparison.load('enums'));

    for (final (name, reference) in <(String, Object? Function())>[
      ('enumValues', sdk.enumValues),
      ('enumIdentity', sdk.enumIdentity),
      ('enumValuesImmutable', sdk.enumValuesImmutable),
      ('enhancedConstructors', sdk.enhancedConstructors),
      ('genericEnumValues', sdk.genericEnumValues),
      ('genericEnumTypes', sdk.genericEnumTypes),
      ('genericEnumStringForms', sdk.genericEnumStringForms),
      ('classEnumStaticConstants', sdk.classEnumStaticConstants),
      ('genericEnumInterfaceDispatch', sdk.genericEnumInterfaceDispatch),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }

    for (final (name, reference) in <(String, Object? Function(int))>[
      ('enumStringForms', sdk.enumStringForms),
      ('enumSwitch', sdk.enumSwitch),
      ('enumSwitchStatement', sdk.enumSwitchStatement),
      ('enumConstantPattern', sdk.enumConstantPattern),
      ('enumObjectPattern', sdk.enumObjectPattern),
    ]) {
      test('$name matches the SDK for each value', () {
        for (var index = 0; index < 3; index++) {
          fixture.compare(name, [index], () => reference(index));
        }
      });
    }

    for (final (name, reference) in <(String, Object? Function(int))>[
      ('customEnumNames', sdk.customEnumNames),
      ('privateEnumGetter', sdk.privateEnumGetter),
    ]) {
      test('$name preserves user declarations and enum metadata', () {
        for (var index = 0; index < 2; index++) {
          fixture.compare(name, [index], () => reference(index));
        }
      });
    }

    for (final (name, reference) in <(String, Object? Function(int))>[
      ('enhancedMembers', sdk.enhancedMembers),
      ('enhancedClosures', sdk.enhancedClosures),
    ]) {
      test('$name matches the SDK', () {
        for (final amount in [-3, 0, 7]) {
          fixture.compare(name, [amount], () => reference(amount));
        }
      });
    }

    for (final (name, reference) in <(String, Object? Function(bool))>[
      ('enhancedFactories', sdk.enhancedFactories),
      ('enumReceivers', sdk.enumReceivers),
      ('enumObjectInterpolation', sdk.enumObjectInterpolation),
      ('enumShorthand', sdk.enumShorthand),
      ('nullableEnum', sdk.nullableEnum),
      ('enumBoundReceivers', sdk.enumBoundReceivers),
    ]) {
      test('$name matches the SDK', () {
        for (final flag in [false, true]) {
          fixture.compare(name, [flag], () => reference(flag));
        }
      });
    }

    test('enum interfaces dispatch getters, methods and tearoffs', () {
      for (var index = 0; index < 3; index++) {
        for (final amount in [-3, 0, 7]) {
          fixture.compare('enumInterfaceDispatch', [
            index,
            amount,
          ], () => sdk.enumInterfaceDispatch(index, amount));
        }
      }
    });

    test('generic enum methods and closures retain actual type arguments', () {
      for (final candidate in <Object?>[null, 4, 2.5, 'x', true]) {
        fixture.compare('genericEnumChecks', [
          candidate,
        ], () => sdk.genericEnumChecks(candidate));
      }
    });
  });

  group('unsupported enum constructs', () {
    for (final (name, source) in <(String, String)>[
      (
        'mixins',
        'mixin Extra { int get score => 1; }\n'
            'enum E with Extra { a }\n'
            'int f() => E.a.score;',
      ),
      (
        'mutable static storage',
        'enum E { a; static int count = 0; }\n'
            'int f() => E.count;',
      ),
      (
        'EnumByName.byName',
        'enum E { a, b }\n'
            "E f() => E.values.byName('a');",
      ),
      (
        'EnumByName.asNameMap',
        'enum E { a, b }\n'
            'Map<String, E> f() => E.values.asNameMap();',
      ),
      (
        'Object-typed toString call',
        'enum E { a }\n'
            'String f() { Object value = E.a; return value.toString(); }',
      ),
      (
        'Object-typed toString tearoff',
        'enum E { a }\n'
            'String f() { Object value = E.a; final describe = value.toString; '
            'return describe(); }',
      ),
      (
        'Enum.compareByName',
        'enum E { a, b }\n'
            'int f() => Enum.compareByName(E.a, E.b);',
      ),
      (
        'Enum.compareByIndex',
        'enum E { a, b }\n'
            'int f() => Enum.compareByIndex(E.b, E.a);',
      ),
    ]) {
      test('$name fails explicitly at its source', () async {
        final directory = Directory.systemTemp.createTempSync('dartc-enum-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        await expectLater(
          CheckedLibraries.read([file.path], Lowering.lower),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'source',
              contains('entry.dart:'),
            ),
          ),
        );
      });
    }

    for (final (name, declaration) in <(String, String)>[
      ('field formal', 'a(7); final int _name; const Broken(this._name);'),
      ('field initializer', 'a; final int _name = 7; const Broken();'),
      (
        'string storage',
        "a('own'); final String _name; const Broken(this._name);",
      ),
    ]) {
      test('rejects enum _name $name rather than corrupting storage', () async {
        final directory = Directory.systemTemp.createTempSync('dartc-enum-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(
            'enum Broken { $declaration }\nObject f() => Broken.a._name;',
          );
        await expectLater(
          CheckedLibraries.read([file.path], Lowering.lower),
          throwsA(
            isA<UnsupportedError>()
                .having(
                  (error) => error.message,
                  'source',
                  contains('entry.dart:'),
                )
                .having((error) => error.message, 'reason', contains('_name')),
          ),
        );
      });
    }

    test(
      'rejects _name storage reached through cross-library constants',
      () async {
        final directory = Directory.systemTemp.createTempSync('dartc-enum-');
        addTearDown(() => directory.deleteSync(recursive: true));
        File('${directory.path}/dependency.dart').writeAsStringSync(
          'enum Broken { a(7); final int _name; const Broken(this._name); }\n'
          'const alias = Broken.a;\n'
          'const nested = <Object>[alias];\n'
          'const record = (alias,);\n'
          'const folded = identical(alias, Broken.a);',
        );
        final entry = File('${directory.path}/entry.dart');
        for (final expression in [
          'd.alias',
          'd.nested',
          'd.record',
          'd.folded',
        ]) {
          entry.writeAsStringSync(
            "import 'dependency.dart' as d; Object f() => $expression;",
          );
          await expectLater(
            CheckedLibraries.read([entry.path], Lowering.lower),
            throwsA(
              isA<UnsupportedError>()
                  .having(
                    (error) => error.message,
                    'use site',
                    contains('entry.dart:'),
                  )
                  .having(
                    (error) => error.message,
                    'reason',
                    contains('_name'),
                  ),
            ),
            reason: expression,
          );
        }
        entry.writeAsStringSync(
          "import 'dependency.dart' as d; int f() => 42;",
        );
        await CheckedLibraries.read([entry.path], Lowering.lower);
      },
    );
  });
}
