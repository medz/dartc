import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/invocations.dart' as sdk;

void main() {
  group('public Invocation objects', () {
    late FixtureComparison fixture;
    setUpAll(() async => fixture = await FixtureComparison.load('invocations'));

    for (final (name, expected) in <(String, Object? Function())>[
      ('invocationTearoffIdentity', sdk.invocationTearoffIdentity),
      ('invocationSnapshots', sdk.invocationSnapshots),
      ('invocationEmptySnapshots', sdk.invocationEmptySnapshots),
      ('invocationReifiedTypes', sdk.invocationReifiedTypes),
      ('invocationCustomGetters', sdk.invocationCustomGetters),
      ('invocationInheritedTypes', sdk.invocationInheritedTypes),
      ('invocationNamedSymbolIdentity', sdk.invocationNamedSymbolIdentity),
      ('invocationOverriddenDefaults', sdk.invocationOverriddenDefaults),
    ]) {
      test('$name matches the Dart SDK', () {
        fixture.compare(name, [], expected);
      });
    }

    test(
      'all four direct and torn-off factories expose their arguments and flags',
      () {
        for (var kind = 0; kind < 4; kind++) {
          for (final tearoff in [false, true]) {
            for (final nullArguments in [false, true]) {
              fixture.compare('invocationFactories', [
                kind,
                tearoff,
                nullArguments,
              ], () => sdk.invocationFactories(kind, tearoff, nullArguments));
            }
          }
        }
      },
    );

    test('omitted and explicit null factory defaults agree', () {
      for (final generic in [false, true]) {
        for (final tearoff in [false, true]) {
          for (final explicitNull in [false, true]) {
            fixture.compare('invocationDefaults', [
              generic,
              tearoff,
              explicitNull,
            ], () => sdk.invocationDefaults(generic, tearoff, explicitNull));
          }
        }
      }
    });

    test(
      'all factories preserve the supplied builtin or custom Symbol identity',
      () {
        for (var kind = 0; kind < 4; kind++) {
          for (final custom in [false, true]) {
            fixture.compare('invocationSymbolIdentity', [
              kind,
              custom,
            ], () => sdk.invocationSymbolIdentity(kind, custom));
          }
        }
      },
    );

    test('named arguments preserve insertion order and snapshot values', () {
      for (final generic in [false, true]) {
        fixture.compare('invocationNamedOrder', [
          generic,
        ], () => sdk.invocationNamedOrder(generic));
      }
    });

    test('collection copies and canonical empties match the pinned SDK', () {
      for (var kind = 0; kind < 4; kind++) {
        for (var inputKind = 0; inputKind < 5; inputKind++) {
          fixture.compare('invocationCollectionIdentity', [
            kind,
            inputKind,
          ], () => sdk.invocationCollectionIdentity(kind, inputKind));
        }
        for (final empty in [false, true]) {
          fixture.compare('invocationCollectionTypes', [
            kind,
            empty,
          ], () => sdk.invocationCollectionTypes(kind, empty));
        }
      }
    });

    test(
      'every argument collection rejects mutation, including empty collections',
      () {
        for (var kind = 0; kind < 4; kind++) {
          for (var target = 0; target < 5; target++) {
            for (final empty in [false, true]) {
              fixture.compare('invocationMutation', [
                kind,
                target,
                empty,
              ], () => sdk.invocationMutation(kind, target, empty));
            }
          }
        }
      },
    );

    test(
      'type checks and object patterns accept builtin and custom Invocations',
      () {
        for (var kind = 0; kind < 8; kind++) {
          fixture.compare('invocationTypeChecks', [
            kind,
          ], () => sdk.invocationTypeChecks(kind));
          fixture.compare('invocationObjectPattern', [
            kind,
          ], () => sdk.invocationObjectPattern(kind));
        }
      },
    );

    test(
      'inherited isAccessor calls virtual getters in short-circuit order',
      () {
        for (final getter in [false, true]) {
          for (final setter in [false, true]) {
            for (final failGetter in [false, true]) {
              for (final failSetter in [false, true]) {
                for (final superAccess in [false, true]) {
                  fixture.compare(
                    'invocationInheritedAccessor',
                    [getter, setter, failGetter, failSetter, superAccess],
                    () => sdk.invocationInheritedAccessor(
                      getter,
                      setter,
                      failGetter,
                      failSetter,
                      superAccess,
                    ),
                  );
                }
              }
            }
          }
        }
      },
    );

    test(
      'factory snapshots obey iterable/map protocols and propagate failures',
      () {
        for (final failure in [
          0,
          11,
          12,
          13,
          14,
          15,
          21,
          22,
          23,
          24,
          25,
          31,
          32,
        ]) {
          for (final emptyMap in [false, true]) {
            for (final tearoff in [false, true]) {
              fixture.compare('invocationCopyProtocols', [
                failure,
                emptyMap,
                tearoff,
              ], () => sdk.invocationCopyProtocols(failure, emptyMap, tearoff));
            }
          }
        }
      },
    );

    test(
      'custom List and Set sources use the SDK length and iterator protocol',
      () {
        for (var kind = 0; kind < 3; kind++) {
          final marker = kind == 1 ? 10 : 20;
          for (final reportedLength in [-1, 0, 1, 2, 3]) {
            for (final failure in [
              0,
              marker + 1,
              marker + 2,
              marker + 3,
              marker + 4,
              marker + 5,
              marker + 6,
            ]) {
              fixture.compare(
                'invocationListProtocols',
                [kind, reportedLength, failure],
                () =>
                    sdk.invocationListProtocols(kind, reportedLength, failure),
              );
              fixture.compare(
                'invocationSetProtocols',
                [kind, reportedLength, failure],
                () => sdk.invocationSetProtocols(kind, reportedLength, failure),
              );
            }
          }
        }
      },
    );

    for (final (name, expected)
        in <(String, String Function(bool, bool, bool, bool))>[
          ('invocationRedeclaredDefaults', sdk.invocationRedeclaredDefaults),
          ('invocationInterfaceDefaults', sdk.invocationInterfaceDefaults),
        ]) {
      test('$name dispatches inherited defaults and user overrides', () {
        for (final getter in [false, true]) {
          for (final failSetter in [false, true]) {
            for (final override in [false, true]) {
              for (final pattern in [false, true]) {
                fixture.compare(name, [
                  getter,
                  failSetter,
                  override,
                  pattern,
                ], () => expected(getter, failSetter, override, pattern));
              }
            }
          }
        }
      });
    }
  });
}
