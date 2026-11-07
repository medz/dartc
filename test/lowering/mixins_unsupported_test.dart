import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test('unmodeled superclass cannot lose application covariance', () async {
    await expectLater(
      CheckedLibraries.read([
        'test/lowering/fixtures/mixin_imported_application.dart',
      ], Lowering.lower),
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
