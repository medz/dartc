@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['basic', 'state', 'types', 'composition']) {
    test('native mixins preserve $group contracts', () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/mixins.dart',
        group,
      ]);
      final native = await Process.run(
        NativeAssets(Target.host()).file('compiler/entry_mixins').absolute.path,
        [group],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      for (final result in [reference, native]) {
        expect(
          result.exitCode,
          0,
          reason: result.stdout.toString() + result.stderr.toString(),
        );
        expect(result.stderr, isEmpty);
      }
      expect(native.stdout, reference.stdout);
      final expected = switch (group) {
        'state' => [
          '["independentState",null,"2:1:1:1:1:1:2",null,[]]',
          '["independentLazyState",null,"0:1:2:3:4:1:2:3:4:4",null,[]]',
          '["lazyAssignmentSkipsOnlyOwnInitializer",null,"90:1:1",null,[]]',
          '["independentLateFinalWrites",null,"10:20:0",null,[]]',
          '["lateFinalSecondWrite",null,true,null,[]]',
          '["lateReadDoesNotBorrowOtherSlot",null,true,null,[]]',
        ],
        'types' => [
          '["covariance",null,"field;method;bound;",null,[]]',
          '["constants",null,"constant:14:true",null,[]]',
          '["nested",null,"nested:16:true:true",null,[]]',
        ],
        'composition' => [
          '["composedGenerators",null,"133:333:333:333",null,[]]',
          '["composedObjectMembers",null,"base:first:true",null,[]]',
          '["composedUnionTypes",null,4,null,[]]',
          '["retainedGenerator",null,333,null,[]]',
        ],
        _ => [
          '["privateMembers",null,"99:41:41:41:true",null,[]]',
          '["aliasConstructorTearoffs",null,"3:6:5:7:8",null,[10,10,11,11,12]]',
          '["superMembers",null,"9:9:20:50:10:10:false:true:true",null,[10]]',
        ],
      };
      expect(
        const LineSplitter().convert(native.stdout.toString()),
        containsAll(expected),
      );
    });
  }
}
