@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('Text converters preserve alphabets, escapes, line boundaries and sink lifetime', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_text_conversion')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(
      result.exitCode,
      0,
      reason: result.stdout.toString() + result.stderr.toString(),
    );
    expect(result.stderr, isEmpty);
    expect(result.stdout, 'text_conversion:ok\n');
  });
}
