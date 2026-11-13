import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/global_storage.dart' as sdk;
import 'fixtures/global_storage/entry.dart' as libraries;

void main() {
  group('global storage SDK comparison', () {
    late FixtureComparison fixture;
    setUpAll(
      () async => fixture = await FixtureComparison.load('global_storage'),
    );

    // A fixture's SDK globals initialize only once. Each function owns separate
    // slots and contains its complete sequence of reads, writes and failures.
    for (final (name, reference) in <(String, Object? Function())>[
      ('directInitializerClosures', sdk.directInitializerClosures),
      ('initializerCastRetries', sdk.initializerCastRetries),
      ('initializerCastRetainsWrite', sdk.initializerCastRetainsWrite),
      ('lateNullableInitializersOnce', sdk.lateNullableInitializersOnce),
      ('throwingNeverRead', sdk.throwingNeverRead),
      ('unboundNeverRead', sdk.unboundNeverRead),
      ('unusedInitializer', sdk.unusedInitializer),
      ('lazyReadOrder', sdk.lazyReadOrder),
      ('defaultNulls', sdk.defaultNulls),
      ('nullableInitializerOnce', sdk.nullableInitializerOnce),
      ('finalInitializerOnce', sdk.finalInitializerOnce),
      ('assignmentSkipsInitializer', sdk.assignmentSkipsInitializer),
      ('compoundUpdates', sdk.compoundUpdates),
      ('coalescingUpdates', sdk.coalescingUpdates),
      ('staticInitializationAndSharing', sdk.staticInitializationAndSharing),
      ('staticOwnerIdentity', sdk.staticOwnerIdentity),
      ('failedInitializerRetries', sdk.failedInitializerRetries),
      (
        'initializerPreservesThrowAndTrace',
        sdk.initializerPreservesThrowAndTrace,
      ),
      ('failedInitializerRetainsWrite', sdk.failedInitializerRetainsWrite),
      (
        'successfulInitializerReplacesWrite',
        sdk.successfulInitializerReplacesWrite,
      ),
      ('finiteMutableRecursion', sdk.finiteMutableRecursion),
      ('finiteFinalRecursion', sdk.finiteFinalRecursion),
      ('finiteLateFinalRecursion', sdk.finiteLateFinalRecursion),
      ('lateInitializerOnce', sdk.lateInitializerOnce),
      ('lateAssignmentSkipsInitializer', sdk.lateAssignmentSkipsInitializer),
      ('lateNullableBinding', sdk.lateNullableBinding),
      ('uninitializedLateRead', sdk.uninitializedLateRead),
      ('lateFinalNullBinding', sdk.lateFinalNullBinding),
      ('lateFinalSecondWrite', sdk.lateFinalSecondWrite),
      ('lateFinalCastBeforeWriteCheck', sdk.lateFinalCastBeforeWriteCheck),
      ('lateCoalescingReadsBeforeRhs', sdk.lateCoalescingReadsBeforeRhs),
      ('lateFinalInitializerOnce', sdk.lateFinalInitializerOnce),
      ('functionStorageAndCallOrder', sdk.functionStorageAndCallOrder),
      ('staticLateStorage', sdk.staticLateStorage),
      ('enumStaticStorage', sdk.enumStaticStorage),
      ('constantsAndExplicitAccessors', sdk.constantsAndExplicitAccessors),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }

    test(
      'constants and explicit accessors do not allocate implicit storage',
      () {
        expect(
          fixture.program.globals.where(
            (slot) =>
                slot.name == 'globalConstant' ||
                slot.name == 'explicitAccessor' ||
                slot.owner?.name == 'ConstantStorage',
          ),
          isEmpty,
        );
        expect(
          fixture.program.functions
              .where((function) => function.target.name == 'explicitAccessor')
              .map((function) => function.target.kind),
          containsAll([FunctionKind.staticGetter, FunctionKind.staticSetter]),
        );
        final generic = fixture.program.globals.singleWhere(
          (slot) =>
              slot.owner?.name == 'GenericStorage' && slot.name == 'count',
        );
        expect(generic.initializer!.kind, FunctionKind.function);
        expect(generic.initializer!.typeParameters, isEmpty);
      },
    );

    test('each runner owns independent lazy storage', () {
      final function = fixture.program.functions.singleWhere(
        (function) => function.target.name == 'runnerIsolation',
      );
      final importedEffects = {
        (
          Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
          'tick',
        ): effects.tick,
      };
      final first = IrInterpreter(fixture.program, importedEffects);
      final second = IrInterpreter(fixture.program, importedEffects);
      effects.calls.clear();
      expect(first.run(function, []), 131);
      expect(first.run(function, []), 132);
      expect(second.run(function, []), 131);
      expect(first.run(function, []), 133);
      expect(second.run(function, []), 132);
      expect(effects.calls, [130, 130]);
    });
  });

  group('global library identity', () {
    test(
      'parts, prefixes, exports and private names resolve declaration slots',
      () async {
        const root = 'test/frontend/lowering/fixtures/global_storage';
        final program = await AnalysisSession([
          '$root/entry.dart',
          '$root/first.dart',
          '$root/second.dart',
          '$root/barrel.dart',
        ]).use((input) async => (await Lowering().lower(input)).program);
        FixtureComparison(program)
            .compare('libraryIdentity', [], libraries.libraryIdentity);
        final firstUri = Uri.base.resolve('$root/first.dart');
        final secondUri = Uri.base.resolve('$root/second.dart');
        expect(
          program.globals.where((slot) => slot.name == 'shared'),
          hasLength(1),
        );
        expect(
          program.globals
              .singleWhere((slot) => slot.name == 'partValue')
              .library,
          firstUri,
        );
        expect(
          program.globals
              .where((slot) => slot.name == '_private')
              .map((slot) => slot.library),
          unorderedEquals([firstUri, secondUri]),
        );
      },
    );

    test('an imported variable without a definition remains an unresolved accessor', () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-global-import-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final dependency = File('${directory.path}/dependency.dart')
        ..writeAsStringSync('int value = 7;');
      final entry = File('${directory.path}/entry.dart')
        ..writeAsStringSync(
          "import 'dependency.dart' as dep; int f() => dep.value;",
        );
      final program = await AnalysisSession([entry.path])
          .use((input) async => (await Lowering().lower(input)).program);
      expect(
        program.globals.where((slot) => slot.library == dependency.uri),
        isEmpty,
      );
      final calls = program.functions
          .singleWhere((f) => f.target.library == entry.uri)
          .blocks
          .expand((block) => block.instructions)
          .whereType<DirectCall>()
          .toList();
      expect(calls, hasLength(1));
      expect(calls.single.target.library, dependency.uri);
      expect(calls.single.target.name, 'value');
      expect(calls.single.target.kind, FunctionKind.staticGetter);
      expect(
        program.functions.map((function) => function.target),
        isNot(contains(calls.single.target)),
      );
    });
  });

  group('global storage language checks', () {
    for (final (name, source) in <(String, String)>[
      (
        'top-level final assignment',
        'final int value = 1; void f() { value = 2; }',
      ),
      (
        'static final assignment',
        'class C { static final int value = 1; } void f() { C.value = 2; }',
      ),
      (
        'enum final assignment',
        'enum E { a; static final int value = 1; } void f() { E.value = 2; }',
      ),
      (
        'initialized late final assignment',
        'late final int value = 1; void f() { value = 2; }',
      ),
      (
        'initialized static late final assignment',
        'class C { static late final int value = 1; } void f() { C.value = 2; }',
      ),
      ('uninitialized non-null top-level', 'int value; int f() => value;'),
      (
        'uninitialized non-null static',
        'class C { static int value; } int f() => C.value;',
      ),
    ]) {
      test('$name is rejected by checked analysis', () async {
        final directory = Directory.systemTemp.createTempSync(
          'dartc-global-invalid-',
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
