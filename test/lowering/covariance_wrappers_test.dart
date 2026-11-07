import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/covariance_wrappers.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('covariance_wrappers');
  });
  test('own wrappers preserve defaults, constructor dispatch, lexical super and real bodies', () {
    for (var form = 0; form < 11; form++) {
      fixture.compare('ownWrapper', [form], () => sdk.ownWrapper(form));
    }
  });
  test('named reordering, flattened chains and nSM replacement eligibility match SDK', () {
    for (var form = 0; form < 4; form++) {
      for (final value in [7, 1.5, 'bad', null]) {
        fixture.compare('namedWrapper', [
          form,
          value,
        ], () => sdk.namedWrapper(form, value));
      }
    }
  });
  test(
    'generic owners and method binders preserve applied types and checks',
    () {
      for (var form = 0; form < 5; form++) {
        for (final value in [7, 'bad', null]) {
          fixture.compare('genericWrapper', [
            form,
            value,
          ], () => sdk.genericWrapper(form, value));
        }
      }
    },
  );
  test('void and Never preserve ordinary forwarding results', () {
    for (var form = 0; form < 2; form++) {
      fixture.compare('resultWrapper', [form], () => sdk.resultWrapper(form));
      fixture.compare('provenanceWrapper', [
        form,
      ], () => sdk.provenanceWrapper(form));
    }
  });
  test('wrappers are ordinary direct calls, flattened without losing newest defaults', () {
    final functions = fixture.program.functions;
    final newest = functions.singleWhere(
      (f) => f.target.owner?.name == 'NamedLatest' && f.target.name == 'f',
    );
    final call = newest.blocks
        .expand((b) => b.instructions)
        .whereType<DirectCall>()
        .single;
    expect(call.target.owner?.name, 'NamedOriginal');
    expect(newest.defaults.values.map((v) => (v as ScalarConstant).value), [
      30,
      31,
    ]);
    expect(
      newest.blocks.expand((b) => b.instructions).whereType<MakeInvocation>(),
      isEmpty,
    );
  });
}
