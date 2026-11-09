import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/forwarder_result_casts.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('forwarder_result_casts');
  });
  test('only provably accepted result casts are omitted', () {
    for (final name in [
      'any',
      'nullableObject',
      'ignored',
      'narrow',
      'generic',
      'impossible',
    ]) {
      final body = fixture.program.functions.singleWhere(
        (f) => f.target.owner?.name == 'ResultBox' && f.target.name == name,
      );
      expect(body.blocks, hasLength(1));
      expect(body.entry.instructions.whereType<MakeInvocation>(), hasLength(1));
      expect(body.entry.instructions.whereType<InstanceCall>(), hasLength(1));
      expect(
        body.entry.instructions.whereType<TypeCast>(),
        hasLength(['narrow', 'generic', 'impossible'].contains(name) ? 1 : 0),
      );
      expect(
        body.entry.end,
        name == 'impossible' ? isA<Unreachable>() : isA<Return>(),
      );
    }
  });
  test(
    'SDK result behavior including null, records, narrow failures and Never',
    () {
      for (var form = 0; form < 6; form++) {
        for (final value in [null, 7, 'text', (1, 'record')]) {
          fixture.compare('forwardResult', [
            form,
            value,
          ], () => sdk.forwardResult(form, value));
        }
      }
    },
  );
}
