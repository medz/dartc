@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'records preserve fields, types, dispatch, equality and GC roots',
    () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/records.dart',
      ]);
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_records')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      for (final result in [reference, native]) {
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
      }
      // SDK 3.14 skips field comparison for identical records containing NaN.
      Iterable<String> shared(ProcessResult result) => (result.stdout as String)
          .split('\n')
          .where((line) => !line.startsWith('nan record:'));
      expect(shared(native), shared(reference));
      expect(native.stdout, contains('nan record: false\n'));
      expect(reference.stdout, contains('true,false,true\n'));
      expect(
        reference.stdout,
        contains('799980000,(item 42, label: kept 中文🙂, nested: (1, 2))'),
      );
    },
  );
}
