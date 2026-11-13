import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

void main() {
  test(
    'accepts nullable results, promoted functions and null-aware calls',
    () async {
      await AnalysisSession([
        'test/frontend/analysis/fixtures/nullable_instantiations/valid.dart',
      ]).use((_) {});
    },
  );
  for (final fixture in ['value', 'method', 'ffi']) {
    test('rejects unused nullable $fixture instantiations', () async {
      await expectLater(
        AnalysisSession([
          'test/frontend/analysis/fixtures/nullable_instantiations/$fixture.dart',
        ]).use((_) => fail('Nullable instantiation passed static checking.')),
        throwsFormatException,
      );
    });
  }
}
