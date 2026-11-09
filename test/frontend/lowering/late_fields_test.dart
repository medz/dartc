import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/late_fields.dart' as sdk;
import 'fixtures/late_fields/second.dart' as libraries;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async => fixture = await FixtureComparison.load('late_fields'));

  group('instance late fields SDK comparison', () {
    for (final (name, reference) in <(String, Object? Function())>[
      (
        'constructorDoesNotInitializeLate',
        sdk.constructorDoesNotInitializeLate,
      ),
      (
        'lazyReadOrderAndInstanceIsolation',
        sdk.lazyReadOrderAndInstanceIsolation,
      ),
      ('constructorBodyTriggersGetter', sdk.constructorBodyTriggersGetter),
      (
        'superBodyTriggersOverriddenGetter',
        sdk.superBodyTriggersOverriddenGetter,
      ),
      (
        'constructorBindingSkipsInitializer',
        sdk.constructorBindingSkipsInitializer,
      ),
      ('finalFieldFormalBindsOnce', sdk.finalFieldFormalBindsOnce),
      ('nullableBoundAndUnbound', sdk.nullableBoundAndUnbound),
      ('finalNullCountsAsFirstWrite', sdk.finalNullCountsAsFirstWrite),
      ('unboundNullableRead', sdk.unboundNullableRead),
      ('unboundCoalescingReadsBeforeRhs', sdk.unboundCoalescingReadsBeforeRhs),
      ('assignmentSkipsInitializer', sdk.assignmentSkipsInitializer),
      ('compoundAndCoalescingUpdates', sdk.compoundAndCoalescingUpdates),
      ('finalSecondWriteEvaluatesRhs', sdk.finalSecondWriteEvaluatesRhs),
      ('finalCastPrecedesBoundCheck', sdk.finalCastPrecedesBoundCheck),
      ('failedFirstCastLeavesUnbound', sdk.failedFirstCastLeavesUnbound),
      ('explicitOverridesAndSuper', sdk.explicitOverridesAndSuper),
      (
        'overriddenFieldsKeepSeparateSlots',
        sdk.overriddenFieldsKeepSeparateSlots,
      ),
      ('failedInitializerRetries', sdk.failedInitializerRetries),
      (
        'initializerPreservesThrowAndTrace',
        sdk.initializerPreservesThrowAndTrace,
      ),
      ('initializerFailureRetainsWrite', sdk.initializerFailureRetainsWrite),
      ('initializerReturnReplacesWrite', sdk.initializerReturnReplacesWrite),
      (
        'initializerCastFailureRetainsWrite',
        sdk.initializerCastFailureRetainsWrite,
      ),
      ('initializerCastFailureRetries', sdk.initializerCastFailureRetries),
      ('finiteMutableRecursion', sdk.finiteMutableRecursion),
      ('finiteFinalRecursion', sdk.finiteFinalRecursion),
      (
        'recursiveFinalCastPrecedesBoundCheck',
        sdk.recursiveFinalCastPrecedesBoundCheck,
      ),
      ('genericInitializerEnvironment', sdk.genericInitializerEnvironment),
      (
        'genericInitializerUsesActualType',
        sdk.genericInitializerUsesActualType,
      ),
      ('mutableGenericCovariantWrite', sdk.mutableGenericCovariantWrite),
      ('genericMutableCollectionWrite', sdk.genericMutableCollectionWrite),
      ('genericMutableFunctionWrite', sdk.genericMutableFunctionWrite),
      ('genericMutableNullableWrite', sdk.genericMutableNullableWrite),
      ('explicitCovariantFinalWrite', sdk.explicitCovariantFinalWrite),
      ('inheritedCovariantFinalWrite', sdk.inheritedCovariantFinalWrite),
      (
        'primaryDeclaringFieldInLateInitializer',
        sdk.primaryDeclaringFieldInLateInitializer,
      ),
      (
        'multipleConstructorsShareInitializerBody',
        sdk.multipleConstructorsShareInitializerBody,
      ),
      ('functionReadBeforeArguments', sdk.functionReadBeforeArguments),
      (
        'unboundFunctionReadBeforeArguments',
        sdk.unboundFunctionReadBeforeArguments,
      ),
      ('unboundNeverGetter', sdk.unboundNeverGetter),
      ('throwingNeverInitializer', sdk.throwingNeverInitializer),
      ('throwingFinalNeverInitializer', sdk.throwingFinalNeverInitializer),
      ('neverInitializerRetries', sdk.neverInitializerRetries),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }

    test('late initializers are distinct receiver-bound bodies', () {
      final lateFields = fixture.program.classes
          .expand((declaration) => declaration.fields)
          .where((field) => field.isLate)
          .toList();
      expect(lateFields, isNotEmpty);
      final initialized = lateFields.where(
        (field) => field.initializer != null,
      );
      final targets = initialized.map((field) => field.initializer!).toList();
      expect(targets.toSet(), hasLength(targets.length));
      for (final field in initialized) {
        final target = field.initializer!;
        expect(target.kind, FunctionKind.fieldInitializer);
        expect(target.kind.hasReceiver, isTrue);
        expect(target.owner, field.owner);
        expect(target.typeParameters, isEmpty);
        expect(
          fixture.program.functions.where((body) => body.target == target),
          hasLength(1),
        );
      }
      final callback = lateFields.singleWhere(
        (field) =>
            field.owner.name == 'MultipleConstructors' &&
            field.name == 'callback',
      );
      expect(callback.initializer, isNotNull);
    });
  });

  group('late-final specification safety with a known SDK difference', () {
    test('implicit covariance rejects unsound writes', () {
      // Dart 3.13.7 JIT and AOT currently return 1.5, although the receiver is
      // ImplicitCovariantFinal<int>. This is NOT an SDK-equivalence test.
      // A future SDK that correctly rejects the write is also accepted here.
      // The front end still documents missing late-final setter type checks:
      // https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/fragment/field/declaration.dart#L914-L934
      final function = fixture.program.functions.singleWhere(
        (body) =>
            body.target.name == 'implicitCovariantFinalKnownSdkDifference',
      );
      expect(
        () => IrInterpreter(fixture.program, {}).run(function, []),
        throwsA(isA<TypeError>()),
      );
      Object? sdkOutcome;
      try {
        sdkOutcome = sdk.implicitCovariantFinalKnownSdkDifference();
      } on TypeError {
        sdkOutcome = TypeError;
      }
      expect(sdkOutcome, anyOf(1.5, TypeError));
    });

    test('rejected implicit covariant write leaves the field unbound', () {
      final function = fixture.program.functions.singleWhere(
        (body) =>
            body.target.name ==
            'implicitCovariantFinalFailedWriteLeavesUnbound',
      );
      expect(IrInterpreter(fixture.program, {}).run(function, []), 125);
    });
  });

  group('instance late field library identity', () {
    test(
      'same-name private fields retain distinct declaring-library slots',
      () async {
        const root = 'test/frontend/lowering/fixtures/late_fields';
        final program = await AnalysisSession([
          '$root/first.dart',
          '$root/second.dart',
        ]).use((input) async => (await Lowering().lower(input)).program);
        FixtureComparison(
          program,
        ).compare('privateFieldIdentity', [], libraries.privateFieldIdentity);
        final fields = program.classes
            .expand((declaration) => declaration.fields)
            .where((field) => field.name == '_value')
            .toList();
        expect(fields, hasLength(2));
        expect(
          fields.map((field) => field.owner.library),
          unorderedEquals([
            Uri.base.resolve('$root/first.dart'),
            Uri.base.resolve('$root/second.dart'),
          ]),
        );
        expect(fields.toSet(), hasLength(2));
      },
    );
  });

  group('instance late field language checks', () {
    for (final (name, source) in <(String, String)>[
      (
        'initialized late final assignment',
        'class C { late final int value = 1; } void f() { C().value = 2; }',
      ),
      (
        'initialized late final field formal',
        'class C { late final int value = 1; C(this.value); }',
      ),
      (
        'initialized late final initializer list',
        'class C { late final int value = 1; C(int n) : value = n; }',
      ),
      (
        'ordinary primary parameter is unavailable to late initializer',
        'class C(int seed) { late int value = seed; }',
      ),
      (
        'ordinary constructor parameter is unavailable to late initializer',
        'class C { C(int seed); late int value = seed; }',
      ),
    ]) {
      test('$name is rejected before lowering', () async {
        final directory = Directory.systemTemp.createTempSync(
          'dartc-late-invalid-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        var lowered = false;
        await expectLater(
          AnalysisSession([file.path]).use((input) async {
            lowered = true;
            return (await Lowering().lower(input)).program;
          }),
          throwsFormatException,
        );
        expect(lowered, isFalse);
      });
    }
  });
}
