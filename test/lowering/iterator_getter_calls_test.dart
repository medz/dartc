import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/iterator_getter_calls.dart' as sdk;

void main() {
  late FixtureComparison comparison;
  setUpAll(() async {
    comparison = await FixtureComparison.load('iterator_getter_calls');
  });

  test(
    'calls function-valued iterator getters with zero or nonzero arguments',
    () {
      comparison.compare('listZeroCall', [], sdk.listZeroCall);
      comparison.compare('listArgumentCall', [], sdk.listArgumentCall);
      comparison.compare('customZeroCall', [], sdk.customZeroCall);
      final function = comparison.program.functions.singleWhere(
        (f) => f.target.name == 'listZeroCall',
      );
      expect(
        function.blocks.expand((b) => b.instructions).whereType<FunctionCall>(),
        hasLength(1),
      );
    },
  );

  test(
    'virtual getter calls evaluate arguments before the getter and call',
    () {
      for (final value in [1, -1]) {
        comparison.compare('customArgumentCall', [
          value,
        ], () => sdk.customArgumentCall(value));
      }
      comparison.compare('extractedCall', [], sdk.extractedCall);
    },
  );
}
