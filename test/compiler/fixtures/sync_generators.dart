import 'dart:ffi';

import '../../frontend/lowering/fixtures/generators.dart' as cases;
import '../../frontend/lowering/fixtures/generator_composition.dart'
    as composition;
import '../../frontend/lowering/fixtures/effects.dart' as effects;
import 'futures.dart' show Payload, churn;

void check(Object? Function() run) {
  effects.calls.clear();
  final value = run();
  print('$value | ${effects.calls.join(',')}');
}

Iterable<String> retained(
  int integer,
  double floating,
  Pointer<Int8> pointer,
) sync* {
  final value = Payload(integer, 'retained 中文🙂');
  yield 'first';
  yield '${value.id}:${value.text}:$floating:${pointer.address}';
}

void main() {
  for (final run in <Object? Function()>[
    cases.lazyPhases,
    cases.earlyStopAndRepeat,
    cases.stoppedDelegation,
    cases.terminalIterators,
    cases.interleavedCaptures,
    cases.retainedLoopClosures,
    cases.resumedRethrow,
    cases.genericGenerators,
    cases.resultProtocols,
    cases.broadSignatures,
    cases.iteratorLifecycle,
    cases.nullableCurrent,
    cases.dynamicIteration,
    composition.ordinaryExtensionGenerators,
    composition.extensionTypeGenerators,
    composition.genericClassGeneratorCapture,
    composition.patternGenerator,
  ]) {
    check(run);
  }
  for (var mode = 0; mode < 5; mode++) {
    check(() => cases.finalizerTransfers(mode));
    check(() => cases.nestedDelegation(mode));
  }
  for (var mode = 0; mode < 4; mode++) {
    check(() => cases.delegationTypeCheck(mode));
    check(() => cases.delegationFailures(mode));
  }
  for (final flag in [false, true]) {
    check(() => cases.individualYieldChecks(flag));
    check(() => cases.neverDelegation(flag));
    check(() => composition.covariantGeneratorEntry(flag));
  }
  check(() => cases.manyValues(1500).length);
  final iterable = retained(42, 3.25, Pointer<Int8>.fromAddress(1234));
  final a = iterable.iterator, b = iterable.iterator;
  a.moveNext();
  b.moveNext();
  churn();
  a.moveNext();
  print(a.current);
  churn();
  b.moveNext();
  print(b.current);
  print('done');
}
