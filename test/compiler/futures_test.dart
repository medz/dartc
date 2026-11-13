@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'SDK Futures preserve completion, ordering, errors, zones and timers',
    () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/futures.dart',
      ]);
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_futures')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      for (final result in [reference, native]) {
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(
          result.stdout,
          '''constructors: sync,caller,microtask,event = 1,2,3
completers: sync,caller,rejected,async = 3.5
recovered,supplied,second
combinators: first,last;winner
timeout
zones: true,true
lifetime: 42,retained 中文🙂
typed callback: true
42,record;(7, null),failed
''',
        );
      }
    },
  );
}
