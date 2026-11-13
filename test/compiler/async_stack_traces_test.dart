@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'async stacks retain awaiters, suspension sites and exception identity',
    () async {
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_async_stack_traces')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/async_stack_traces.dart',
      ]);
      for (final result in [reference, native]) {
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(result.stderr, isEmpty);
        final output = result.stdout as String;
        expect(output, endsWith('unread-links:ok\n'));
        final expected = {
          'nested': ['stackLeaf', 'stackMiddle', 'stackOuter', 'main'],
          'then': ['thenCallback', 'thenParent', 'main'],
          'wait': ['stackLeaf', 'waitParent', 'main'],
          'timeout': ['stackLeaf', 'timeoutParent', 'main'],
          'stream': ['stackStream', 'delegatedStream', 'streamParent', 'main'],
          'boxed': ['boxedLink.callback', 'boxedParent', 'main'],
          'zone': ['stackLeaf', 'stackMiddle', 'stackOuter', 'main'],
          'wrapped-zone': [
            'stackLeaf',
            'stackMiddle',
            'stackOuter',
            'wrappedZone',
            'main',
          ],
          'completed': ['completedAwait', 'emitDetached', 'main'],
          'rethrow': ['errorLeaf', 'rethrowParent', 'main'],
        };
        for (final entry in expected.entries) {
          final label = entry.key;
          final trace = RegExp(
            'BEGIN $label\n(.*?)END $label',
            dotAll: true,
          ).firstMatch(output)?.group(1);
          expect(trace, isNotNull, reason: output);
          final names = <String>[];
          final frames = RegExp(
            r'^#\d+\s+(\S+) ',
            multiLine: true,
          ).allMatches(trace!).map((match) => match.group(1)!).toList();
          for (final frame in frames) {
            if (entry.value.contains(frame)) names.add(frame);
          }
          expect(names, entry.value, reason: '$label\n$trace');
          expect(trace, contains('<asynchronous suspension>'), reason: label);
          expect(trace, contains('async_stack_traces.dart:'), reason: label);
          if (label == 'nested') {
            expect(
              trace,
              matches(r'stackMiddle \(.*async_stack_traces\.dart:11:43\)'),
            );
            expect(
              trace,
              matches(r'stackOuter \(.*async_stack_traces\.dart:12:42\)'),
            );
          }
        }
      }
    },
  );
}
