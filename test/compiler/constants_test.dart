@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['identity', 'mutation', 'generic']) {
    test('native constants preserve $group contracts', () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/constants.dart',
        group,
      ]);
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_constants')
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
          reason: result.stdout.toString() + result.stderr.toString(),
        );
        expect(result.stderr, isEmpty);
      }
      expect(native.stdout, reference.stdout);
      final expected = switch (group) {
        'identity' => [
          '["rootObjectIdentity",null,true,null,[]]',
          '["importedConstructorAlias",null,true,null,[]]',
          '["canonicalObjects",null,true,null,[]]',
          '["equalityVersusIdentity",null,1,null,[]]',
          '["canonicalCollections",null,true,null,[]]',
          '["widenedRecordCanonicalization",null,7,null,[]]',
          '["orderedCanonicalCollections",null,true,null,[]]',
          '["listReadBounds",null,null,"range",[99]]',
          '["crossLibraryConstants",null,true,null,[]]',
          '["constantPatterns",true,54,null,[5]]',
        ],
        'mutation' => [
          '["listMutation",1,null,"unsupported",[1]]',
          '["listMutation",2,null,"type",[1]]',
          '["listMutation",4,null,"unsupported",[1]]',
          '["mapMutation",1,null,"type",[1]]',
          '["addAllSourceType",[0,true,true],null,"type",[1]]',
          '["literalDynamicSpread",[true,false],null,"type",[10,20,31,20,32]]',
        ],
        _ => [
          '["genericConstantIdentity",null,true,null,[]]',
          '["genericAliasConstantIdentity",null,true,null,[]]',
          '["genericConstantPattern",true,1,null,[]]',
          '["genericConstructorPattern",false,2,null,[]]',
          '["genericInlineAliasPattern",false,2,null,[]]',
          '["genericAliasConstants",5,30,null,[]]',
        ],
      };
      expect(
        const LineSplitter().convert(native.stdout.toString()),
        containsAll(expected),
      );
    });
  }
}
