import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test('validates an explicit SDK without installing or copying it', () {
    final sdk = DartSdk.current();
    expect(sdk.version, isNotEmpty);
    expect(
      File.fromUri(sdk.libraries.uri.resolve('core/core.dart')).existsSync(),
      isTrue,
    );
    expect(() => DartSdk.at('test/compiler/fixtures'), throwsArgumentError);
  });
}
