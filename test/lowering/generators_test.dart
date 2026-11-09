import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../support/ir_interpreter.dart';
import 'fixtures/generators.dart' as sdk;

void main() {
  late FixtureComparison comparison;
  setUpAll(() async {
    comparison = await FixtureComparison.load('generators');
  });

  test('sync* invocation and iterator creation leave the body suspended', () {
    comparison.compare('lazyPhases', [], sdk.lazyPhases);
  });
  test('early stopping does not unwind and new iterations start afresh', () {
    comparison.compare('earlyStopAndRepeat', [], sdk.earlyStopAndRepeat);
    comparison.compare('stoppedDelegation', [], sdk.stoppedDelegation);
    comparison.compare('terminalIterators', [], sdk.terminalIterators);
  });
  test('iterators own local cells and share captured outer cells', () {
    final function = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'interleavedCaptures',
    );
    expect(
      IrInterpreter(comparison.program, {}).run(function, []),
      sdk.interleavedCaptures(),
    );
    comparison.compare('retainedLoopClosures', [], sdk.retainedLoopClosures);
  });
  test(
    'suspension preserves return, catch and nested finally continuations',
    () {
      for (var mode = 0; mode < 5; mode++) {
        comparison.compare('finalizerTransfers', [
          mode,
        ], () => sdk.finalizerTransfers(mode));
      }
    },
  );
  test('rethrow after suspension preserves its original stack trace', () {
    comparison.compare('resumedRethrow', [], sdk.resumedRethrow);
  });
  test(
    'yield* delegates through nested generators and checks its full type',
    () {
      for (var depth = 0; depth < 5; depth++) {
        comparison.compare('nestedDelegation', [
          depth,
        ], () => sdk.nestedDelegation(depth));
      }
      for (var kind = 0; kind < 4; kind++) {
        comparison.compare('delegationTypeCheck', [
          kind,
        ], () => sdk.delegationTypeCheck(kind));
      }
    },
  );
  test(
    'yield* protocol errors enter catches and finalizers at their source',
    () {
      for (var failure = 0; failure < 4; failure++) {
        comparison.compare('delegationFailures', [
          failure,
        ], () => sdk.delegationFailures(failure));
      }
    },
  );
  test(
    'empty Never delegation preserves both ordinary and protected exits',
    () {
      for (final protected in [false, true]) {
        comparison.compare('neverDelegation', [
          protected,
        ], () => sdk.neverDelegation(protected));
      }
    },
  );
  test(
    'generic bodies, closures, methods and getters keep type environments',
    () {
      comparison.compare('genericGenerators', [], sdk.genericGenerators);
      comparison.compare('resultProtocols', [], sdk.resultProtocols);
      comparison.compare('broadSignatures', [], sdk.broadSignatures);
    },
  );
  test('yield conversions and iterator protocols follow the SDK', () {
    for (final valid in [false, true]) {
      comparison.compare('individualYieldChecks', [
        valid,
      ], () => sdk.individualYieldChecks(valid));
    }
    comparison.compare('iteratorLifecycle', [], sdk.iteratorLifecycle);
    comparison.compare('nullableCurrent', [], sdk.nullableCurrent);
    comparison.compare('dynamicIteration', [], sdk.dynamicIteration);
  });
  test('same-activation reentry is a reference-executor boundary', () {
    // The SDK 3.13.7 reference execution crashes on this recursive resume;
    // it does not provide a comparable Dart outcome or a StateError contract.
    final function = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'reentrantIterator',
    );
    expect(
      () => IrInterpreter(comparison.program, {}).run(function, []),
      throwsUnsupportedError,
    );
  });
  test('long iteration has a fresh execution budget after each yield', () {
    final function = comparison.program.functions.singleWhere(
      (f) => f.target.name == 'manyValues',
    );
    final runner = IrInterpreter(comparison.program, {});
    final arguments = <Object?>[1500];
    final values = runner.run(function, arguments) as Iterable<Object?>;
    arguments[0] = 1;
    expect(values.toList(), sdk.manyValues(1500).toList());
  });
  test('generator mode and resume edges remain visible in the public IR', () {
    final generators = comparison.program.functions.where(
      (f) => f.bodyKind == FunctionBodyKind.syncGenerator,
    );
    expect(generators, isNotEmpty);
    for (final function in generators) {
      expect(function.yieldType, isNotNull);
      final output = StringBuffer();
      function.writeTo(output);
      expect(output.toString(), contains('sync*<'));
      if (function.blocks.any((block) => block.end is Yield)) {
        expect(output.toString(), contains(' resume b'));
      }
    }
  });
  test(
    'concrete generator implementation runtime types stay explicit boundaries',
    () {
      for (final name in [
        'generatorRuntimeType',
        'generatorIteratorRuntimeType',
      ]) {
        final function = comparison.program.functions.singleWhere(
          (f) => f.target.name == name,
        );
        expect(
          () => IrInterpreter(comparison.program, {}).run(function, []),
          throwsUnsupportedError,
        );
      }
    },
  );
  test('invalid generator return types fail before lowering', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-generators-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final invalid = File('${directory.path}/invalid.dart')
      ..writeAsStringSync('void f() sync* { yield 1; }');
    await expectLater(
      AnalysisSession([invalid.path])
          .use((input) => Lowering().lower(input).program),
      throwsFormatException,
    );
  });
}
