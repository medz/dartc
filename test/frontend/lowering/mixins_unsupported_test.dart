import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

void main() {
  test('unmodeled superclass cannot lose application covariance', () async {
    await expectLater(
      AnalysisSession([
        'test/frontend/lowering/fixtures/mixin_imported_application.dart',
      ]).use((input) async => (await Lowering().lower(input)).program),
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
