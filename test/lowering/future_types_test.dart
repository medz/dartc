import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/future_types.dart' as sdk;

void main() {
  late FixtureComparison comparison;
  setUpAll(() async {
    comparison = await FixtureComparison.load('future_types');
  });

  test('FutureOr checks both value and Future arms including nullability', () {
    for (var kind = 0; kind < 6; kind++) {
      comparison.compare('classify', [kind], () => sdk.classify(kind));
      comparison.compare('castAndAssert', [
        kind,
      ], () => sdk.castAndAssert(kind));
    }
    final checked = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'checkedBang',
    );
    final op = checked.blocks
        .expand((b) => b.instructions)
        .whereType<NullCheck>()
        .single;
    expect(op.type, ValueType.futureOr(ValueType.integer.nullable));
    expect(op.type.mayBeNull, isTrue);
  });

  test(
    'reified FutureOr types normalize after runtime generic substitution',
    () {
      comparison.compare('normalizedTypes', [], sdk.normalizedTypes);
    },
  );

  test('recursive bounds retain valid arguments', () {
    final function = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'recursiveBound',
    );
    // SDK 3.13.7 reference invocation of this legal recursive bound did not
    // complete in the isolated probe. Keep this an explicit IR-only check.
    expect(FixtureRunner(comparison.program, {}).run(function, []), '1:null');
  });
  test('union bounds retain both arms', () {
    comparison.compare('unionBound', [], sdk.unionBound);
  });

  test(
    'a union with two Future arms can upcast without losing its identity',
    () {
      for (final nested in [false, true]) {
        comparison.compare('sharedFutureView', [
          nested,
        ], () => sdk.sharedFutureView(nested));
        comparison.compare('callSharedFuture', [
          nested,
        ], () => sdk.callSharedFuture(nested));
        comparison.compare('widenedFuture', [
          nested,
        ], () => sdk.widenedFuture(nested));
        comparison.compare('callWidenedGeneric', [
          nested,
        ], () => sdk.callWidenedGeneric(nested));
      }
    },
  );

  test('nominal union views are pure and preserve the original object', () {
    for (final name in ['widenedFuture', 'widenedGeneric']) {
      final function = comparison.program.functions.singleWhere(
        (f) => f.target.name == name,
      );
      final views = function.blocks
          .expand((b) => b.instructions)
          .whereType<TypeView>()
          .where(
            (op) => op.type == CoreTypes.futureOf(ValueType.object.nullable),
          );
      expect(views, isNotEmpty, reason: name);
      expect(views.every((op) => !op.mayThrow), isTrue);
    }
    for (final nested in [false, true]) {
      comparison.compare('widenedIdentity', [
        nested,
      ], () => sdk.widenedIdentity(nested));
    }
  });

  test('IR subtyping agrees with analyzer across both union arms', () async {
    final target = comparison.program.functions
        .singleWhere((f) => f.target.name == 'subtypeMatrix')
        .target;
    await AnalysisSession(['test/lowering/fixtures/future_types.dart']).use((
      checked,
    ) {
      final unit = checked.libraries.single.units.single;
      final source = unit.libraryElement.topLevelFunctions.singleWhere(
        (f) => f.name == 'subtypeMatrix',
      );
      final parameters = source.formalParameters;
      for (var i = 0; i < parameters.length; i++) {
        for (var j = 0; j < parameters.length; j++) {
          expect(
            target.parameterTypes[j].accepts(target.parameterTypes[i]),
            unit.typeSystem.isSubtypeOf(parameters[i].type, parameters[j].type),
            reason: '${parameters[i].type} <: ${parameters[j].type}',
          );
        }
      }
    });
  });

  test('native Future type checks remain an explicit executor boundary', () {
    final function = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'checkNative',
    );
    expect(
      () => FixtureRunner(
        comparison.program,
        {},
      ).run(function, [Future<int>.value(1)]),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'feature',
          contains('Native Future runtime type checks'),
        ),
      ),
    );
  });
}
