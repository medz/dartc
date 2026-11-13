@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['collections', 'objects']) {
    test(
      'native $group patterns preserve values, errors and effect order',
      () async {
        final reference = await Process.run(Platform.resolvedExecutable, [
          'test/compiler/fixtures/patterns.dart',
          group,
        ]);
        final native = await Process.run(
          NativeAssets(Target.host())
              .file('compiler/entry_patterns')
              .absolute
              .path,
          [group],
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        for (final result in [reference, native]) {
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}${result.stderr}',
          );
          expect(result.stderr, isEmpty);
        }
        expect(native.stdout, reference.stdout);
        final expected = group == 'collections'
            ? [
                [
                  'assignmentAtomic',
                  0,
                  78,
                  null,
                  [1, 90],
                ],
                [
                  'nestedAssignmentAtomic',
                  0,
                  78,
                  null,
                  [1, 90],
                ],
                [
                  'castAssignmentAtomic',
                  0,
                  78,
                  null,
                  [90],
                ],
                [
                  'contextualNestedAssignment',
                  0,
                  78,
                  null,
                  [90],
                ],
                ['contextualRecordFields', 0, null, 'type', []],
                ['genericPatterns', 0, 111, null, []],
              ]
            : [
                [
                  'orderedDerived',
                  0,
                  11,
                  null,
                  [10, 1, 1],
                ],
                [
                  'assignObject',
                  -1,
                  300,
                  null,
                  [9, -1],
                ],
                [
                  'guardedMutationObject',
                  1,
                  12,
                  null,
                  [1],
                ],
                [
                  'nestedGetterObject',
                  0,
                  10,
                  null,
                  [50, 0, 10],
                ],
              ];
        for (final observation in expected) {
          expect(native.stdout, contains(jsonEncode(observation)));
        }
      },
    );
  }
}
