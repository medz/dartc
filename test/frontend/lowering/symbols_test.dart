import 'dart:io';

import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/symbols.dart' as sdk;

void main() {
  group('public Symbols', () {
    late FixtureComparison fixture;
    setUpAll(() async => fixture = await FixtureComparison.load('symbols'));

    for (final (name, expected) in <(String, Object? Function())>[
      ('symbolLiterals', sdk.symbolLiterals),
      ('symbolConstants', sdk.symbolConstants),
      ('symbolArbitraryConstants', sdk.symbolArbitraryConstants),
      ('symbolPrivateNameConstructors', sdk.symbolPrivateNameConstructors),
      ('symbolPublicLibraries', sdk.symbolPublicLibraries),
      ('symbolRuntimeStaticIdentity', sdk.symbolRuntimeStaticIdentity),
      ('symbolStaticNames', sdk.symbolStaticNames),
      ('symbolNestedConstants', sdk.symbolNestedConstants),
      ('symbolDefaultValues', sdk.symbolDefaultValues),
      ('symbolEvaluationOrder', sdk.symbolEvaluationOrder),
      ('symbolConstructorOrder', sdk.symbolConstructorOrder),
      ('symbolTypeChecks', sdk.symbolTypeChecks),
      ('symbolGenericCollections', sdk.symbolGenericCollections),
      ('symbolNestedPatterns', sdk.symbolNestedPatterns),
      ('symbolUserEquality', sdk.symbolUserEquality),
      ('symbolUserAsymmetry', sdk.symbolUserAsymmetry),
      ('symbolUserConstants', sdk.symbolUserConstants),
      ('symbolUserText', sdk.symbolUserText),
      ('symbolUserCollections', sdk.symbolUserCollections),
      ('symbolOrdinarySuperHash', sdk.symbolOrdinarySuperHash),
      ('symbolSuperHashStability', sdk.symbolSuperHashStability),
    ]) {
      test('$name matches the Dart SDK', () {
        fixture.compare(name, [], expected);
      });
    }

    const names = [
      '',
      'alpha',
      'beta',
      '_private',
      'foo.bar',
      'foo._bar',
      '_foo.bar',
      'alpha=',
      'unary-',
      '[]',
      '[]=',
      '>>>',
      'a b',
      ' leading and trailing ',
      '\t\n',
      '"quoted"',
      "a'b",
      'line\nend',
      'back\\slash',
      '\u0000',
      'Σ🌈',
      'get:foo',
      'set:foo',
      'abc@123',
      'abc@123.def@456',
    ];
    for (final (name, expected) in <(String, Object? Function(String))>[
      ('symbolRuntimeIdentity', sdk.symbolRuntimeIdentity),
      ('symbolRuntimeText', sdk.symbolRuntimeText),
      ('symbolBoundText', sdk.symbolBoundText),
      ('symbolConstructorTearoffs', sdk.symbolConstructorTearoffs),
      ('symbolGenericAlias', sdk.symbolGenericAlias),
      ('symbolConstantPattern', sdk.symbolConstantPattern),
    ]) {
      test('$name matches the Dart SDK for arbitrary names', () {
        for (final value in names) {
          fixture.compare(name, [value], () => expected(value));
        }
      });
    }

    test('direct and torn-off Symbol constructors check dynamic arguments', () {
      for (final value in <Object?>[
        'alpha',
        'arbitrary name',
        null,
        42,
        true,
      ]) {
        for (final tearoff in [false, true]) {
          fixture.compare('symbolCheckedArgument', [
            value,
            tearoff,
          ], () => sdk.symbolCheckedArgument(value, tearoff));
        }
      }
    });

    test('Symbol equality uses raw names even when VM text is the same', () {
      for (final (raw, plain) in [
        ('get:foo', 'foo'),
        ('set:foo', 'foo='),
        ('abc@123', 'abc'),
        ('abc@123.def@456', 'abc.def'),
      ]) {
        fixture.compare('symbolRawNameEquality', [
          raw,
          plain,
        ], () => sdk.symbolRawNameEquality(raw, plain));
      }
    });

    test('super.hashCode bypasses Symbol user overrides once', () {
      for (final erase in [false, true]) {
        fixture.compare('symbolUserSuperHash', [
          erase,
        ], () => sdk.symbolUserSuperHash(erase));
      }
    });

    test('Symbol object patterns match builtin and user implementations', () {
      for (var kind = 0; kind < 5; kind++) {
        fixture.compare('symbolObjectPattern', [
          kind,
        ], () => sdk.symbolObjectPattern(kind));
      }
    });
  });

  test(
    'private Symbol literals and their constant dependencies stay rejected',
    () async {
      final directory = Directory.systemTemp.createTempSync('dartc-symbol-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/entry.dart');
      for (final source in [
        'Object f() => #_private;',
        'Object f() => #_foo.bar;',
        "const hidden = #_private == Symbol('_private'); bool f() => hidden;",
        'class const Box(final Object value); '
            'Object f() => const Box(<Object>[#_private]);',
        'Object f([Object value = const <Object>[#_private]]) => value;',
        'class const Box([final Object value = #_private]); '
            'Object f() => const Box();',
      ]) {
        file.writeAsStringSync(source);
        await expectLater(
          AnalysisSession([file.path])
              .use((input) => Lowering().lower(input).program),
          throwsA(
            isA<UnsupportedError>()
                .having((e) => e.message, 'source', contains('entry.dart:'))
                .having(
                  (e) => e.message,
                  'reason',
                  contains('private Symbol literal'),
                ),
          ),
          reason: source,
        );
      }
    },
  );
}
