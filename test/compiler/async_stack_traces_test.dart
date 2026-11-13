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

  test('pending callbacks retain source units and later awaiters', () async {
    final native = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_callback_stack_locations')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    final reference = await Process.run(Platform.resolvedExecutable, [
      'test/compiler/fixtures/callback_stack_locations.dart',
    ]);
    for (final result in [reference, native]) {
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      final output = result.stdout as String;
      final expected = {
        'top': (r'topCallback', r'callback_stack_locations\.dart:10:1'),
        'generic': (r'genericCallback', r'callback_stack_locations\.dart:11:1'),
        'instance': (
          r'Receiver\.instanceCallback',
          r'callback_stack_locations\.dart:14:3',
        ),
        'constructor': (
          r'TraceBox\.(?:new|TraceBox)',
          'callback_stack_locations\\.dart:17:${identical(result, native) ? 7 : 15}',
        ),
        'factory': (
          r'TraceBox\.(?:TraceBox\.)?copy',
          r'callback_stack_locations\.dart:18:3',
        ),
        'redirect': (
          r'TraceBox\.(?:TraceBox\.)?redirect',
          r'callback_stack_locations\.dart:19:3',
        ),
        'alias': (
          r'TraceBox\.(?:new|TraceBox)',
          'callback_stack_locations\\.dart:17:${identical(result, native) ? 7 : 15}',
        ),
        'part': (r'partCallback', r'callback_stack_locations_part\.dart:3:1'),
        'extension': (
          r'[^\n]*TraceCallbacks(?:\.|:method:)extensionCallback[^\n]*',
          r'callback_stack_locations_part\.dart:7:3',
        ),
        'sdk': (
          r'Future\.wait\.<anonymous(?: closure)?>',
          r'async/future\.dart:567:21',
        ),
      };
      for (final entry in expected.entries) {
        final label = entry.key;
        final trace = RegExp(
          'BEGIN $label\n(.*?)END $label',
          dotAll: true,
        ).firstMatch(output)?.group(1);
        expect(trace, isNotNull, reason: output);
        final (name, source) = entry.value;
        final callbacks = RegExp(
          '^#\\d+\\s+$name \\([^\\n]*$source\\)',
          multiLine: true,
        ).allMatches(trace!).toList();
        expect(callbacks, hasLength(1), reason: trace);
        final leaf = RegExp(
          r'^#\d+\s+leaf ',
          multiLine: true,
        ).firstMatch(trace);
        final parent = RegExp(
          '^#\\d+\\s+${label}Parent ',
          multiLine: true,
        ).firstMatch(trace);
        final main = RegExp(
          r'^#\d+\s+main ',
          multiLine: true,
        ).firstMatch(trace);
        expect(leaf, isNotNull, reason: trace);
        expect(parent, isNotNull, reason: trace);
        expect(main, isNotNull, reason: trace);
        expect(leaf!.start, lessThan(callbacks.single.start), reason: trace);
        expect(callbacks.single.end, lessThan(parent!.start), reason: trace);
        expect(parent.end, lessThan(main!.start), reason: trace);
      }
    }
  });
}
