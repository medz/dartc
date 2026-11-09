import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test('bundled sources contain the pinned SDK and its original license', () {
    final files = const DartSdk().files;
    expect(files['version']!.trim(), DartSdk.version);
    expect(files['revision']!.trim(), DartSdk.sourceRevision);
    expect(files['LICENSE'], contains('Copyright'));
    expect(files['lib/core/core.dart'], contains('library dart.core'));
    expect(files['lib/ffi/ffi.dart'], contains('library dart.ffi'));
    expect(files, contains('lib/libraries.json'));
    expect(() => files['version'] = 'other', throwsUnsupportedError);
  });
}
