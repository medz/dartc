import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

void main() {
  for (final fixture in [
    'duplicate_map',
    'duplicate_set',
    'invalid_argument',
    'invalid_assertion',
    'duplicate_pattern',
  ]) {
    test('private symbol identity retains $fixture diagnostics', () async {
      await expectLater(
        AnalysisSession([
          'test/frontend/analysis/fixtures/symbols/$fixture.dart',
        ]).use((_) => fail('Invalid private Symbol use passed analysis.')),
        throwsFormatException,
      );
    });
  }
}
