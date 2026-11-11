import 'dart:convert';

import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bundled sources contain the pinned SDK and its original license',
    () async {
      final sources = (await DartSdk.load()).sources;
      String read(String path) => utf8.decode(sources.read('sdk/$path'));
      expect(read('version').trim(), DartSdk.version);
      expect(read('revision').trim(), DartSdk.sourceRevision);
      expect(read('LICENSE'), contains('Copyright'));
      expect(read('lib/core/core.dart'), contains('library dart.core'));
      expect(read('lib/ffi/ffi.dart'), contains('library dart.ffi'));
      expect(sources.paths, contains('sdk/lib/libraries.json'));
      expect(() => sources.read('sdk/version')[0] = 0, throwsUnsupportedError);
    },
  );
}
