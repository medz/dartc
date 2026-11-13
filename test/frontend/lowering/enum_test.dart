import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/enums.dart' as sdk;
import 'fixtures/enum_private_storage.dart' as storage;
import 'fixtures/enum_private_storage_use.dart' as imported;

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

  test(
    'enum names and user storage retain separate private identities',
    () async {
      final fixture = await FixtureComparison.load('enum_private_storage');
      for (var index = 0; index < storage.Code.values.length; index++) {
        fixture.compare('privateEnumStorage', [
          index,
        ], () => storage.privateEnumStorage(index));
      }
      fixture.compare(
        'privateEnumInitializers',
        [],
        storage.privateEnumInitializers,
      );
    },
  );

  test(
    'cross-library aliases and nested constants retain enum storage',
    () async {
      final fixture = FixtureComparison(
        await AnalysisSession(
          ['test/frontend/lowering/fixtures/enum_private_storage_use.dart'],
          includeDependencies: true,
        ).use((input) async => (await Lowering().lower(input)).program),
      );
      fixture.compare(
        'crossLibraryEnumStorage',
        [],
        imported.crossLibraryEnumStorage,
      );
    },
  );
}
