@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'enum private fields retain values, names, identity and SDK helpers',
    () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/enums.dart',
      ]);
      final native = await Process.run(
        NativeAssets(Target.host()).file('compiler/entry_enums').absolute.path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      for (final result in [reference, native]) {
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
      }
      expect(native.stdout, reference.stdout);
      expect(native.stdout, contains('7:first:0:Code.first:first\n'));
      expect(
        native.stdout,
        contains('-3:second:second:true:true:true:false:11:33\n'),
      );
      expect(native.stdout, contains('name:missing\n'));
    },
  );
}
