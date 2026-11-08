import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'native_assets.dart';

void main() {
  test('missing assets report the build step without creating files', () {
    final assets = NativeAssets(Target.host());
    expect(
      () => assets.open('missing'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('dart run tool/build_test_assets.dart'),
        ),
      ),
    );
    expect(assets.library('missing').existsSync(), isFalse);
  });
}
