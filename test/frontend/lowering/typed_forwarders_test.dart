import 'package:test/test.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';

import 'fixtures/typed_forwarders_private_use.dart' as private_sdk;
import 'fixture_comparison.dart';
import 'fixtures/typed_forwarders.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load(
      'typed_forwarders',
      sources: await SdkSources.load(),
    );
  });
  test('typed and dynamic bodies receive full bound Invocation arguments', () {
    for (var form = 0; form < 14; form++) {
      fixture.compare('forwardForms', [form], () => sdk.forwardForms(form));
    }
  });
  test('generic owner substitution, applied types and omitted defaults', () {
    for (var form = 0; form < 6; form++) {
      fixture.compare('forwardGenerics', [
        form,
      ], () => sdk.forwardGenerics(form));
    }
  });
  test('entry failures, raw wrong shapes, result casts and throw identity', () {
    for (var form = 0; form < 10; form++) {
      for (final value in [7, 'bad', null]) {
        fixture.compare('forwardFailures', [
          form,
          value,
        ], () => sdk.forwardFailures(form, value));
      }
    }
  });
  test('void results survive while assignments yield RHS and Never casts', () {
    for (var form = 0; form < 7; form++) {
      fixture.compare('forwardVoid', [form], () => sdk.forwardVoid(form));
    }
  });
  test('explicit and owner covariance retain reified tearoff entry checks', () {
    for (var form = 0; form < 7; form++) {
      for (final value in [7, 'bad', null]) {
        fixture.compare('forwardCovariance', [
          form,
          value,
        ], () => sdk.forwardCovariance(form, value));
      }
    }
  });
  test(
    'actual inherited targets preserve defaults, super calls and precedence',
    () {
      for (var form = 0; form < 8; form++) {
        fixture.compare('forwardInheritance', [
          form,
        ], () => sdk.forwardInheritance(form));
      }
    },
  );
  test(
    'unchanged foreign children reuse the actual private forwarder',
    () async {
      final privateFixture = FixtureComparison(
        await AnalysisSession([
          'test/frontend/lowering/fixtures/typed_forwarders_private.dart',
          'test/frontend/lowering/fixtures/typed_forwarders_private_use.dart',
        ]).use((input) async => (await Lowering().lower(input)).program),
      );
      for (var form = 0; form < 3; form++) {
        for (final tearoff in [false, true]) {
          privateFixture.compare('forwardPrivateInheritance', [
            form,
            tearoff,
          ], () => private_sdk.forwardPrivateInheritance(form, tearoff));
        }
      }
    },
  );
  test('super references bind actual inherited bodies and their defaults', () {
    final program = fixture.program;
    final original = program.functions.singleWhere(
      (f) =>
          f.target.owner?.name == 'OriginalForward' &&
          f.target.name == 'inherited',
    );
    final direct = program.functions.singleWhere(
      (f) =>
          f.target.owner?.name == 'ReusedChild' &&
          f.target.name == 'directParent',
    );
    final call = direct.blocks
        .expand((b) => b.instructions)
        .whereType<DirectCall>()
        .single;
    expect(call.target, same(original.target));
    expect((call.inputs.last as ScalarConstant).value, 10);
    final extracted = program.functions.singleWhere(
      (f) =>
          f.target.owner?.name == 'ReusedChild' &&
          f.target.name == 'parentTear',
    );
    final tear = extracted.blocks
        .expand((b) => b.instructions)
        .whereType<BindMethod>()
        .single;
    expect(tear.direct, isTrue);
    expect(tear.method, same(original.target));
  });

  test('typed mirror positional, type and named snapshots are immutable', () {
    for (var form = 0; form < 5; form++) {
      for (var operation = 0; operation < 5; operation++) {
        fixture.compare('forwardImmutability', [
          form,
          operation,
        ], () => sdk.forwardImmutability(form, operation));
      }
    }
  });
  test(
    'named owner covariance follows names when child parameter slots move',
    () {
      for (var form = 0; form < 4; form++) {
        for (final value in [7, 'bad', null]) {
          fixture.compare('forwardNamedCovariance', [
            form,
            value,
          ], () => sdk.forwardNamedCovariance(form, value));
        }
      }
    },
  );
  test('owner covariance survives multiple nongeneric regenerated bodies', () {
    for (var form = 0; form < 6; form++) {
      for (final value in [7, 'bad', null]) {
        fixture.compare('forwardRepeatedCovariance', [
          form,
          value,
        ], () => sdk.forwardRepeatedCovariance(form, value));
      }
    }
  });
  test('lexical super survives nested closure, generic tearoff and accessor operators', () {
    fixture.compare('forwardSuperOrder', [], sdk.forwardSuperOrder);
  });
}
