import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test('unmodeled superclass cannot lose application covariance', () async {
    await expectLater(
      AnalysisSession([
        'test/lowering/fixtures/mixin_imported_application.dart',
      ]).use((input) => Lowering().lower(input).program),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'reason',
          contains('mixin application with unmodeled superclass'),
        ),
      ),
    );
  });
}
