@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['access', 'call', 'tearoffs', 'order']) {
    test('native extensions preserve $group contracts', () async {
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_extensions')
            .absolute
            .path,
        [group],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(
        native.exitCode,
        0,
        reason: native.stdout.toString() + native.stderr.toString(),
      );
      expect(native.stderr, isEmpty);
      if (group != 'order') {
        final reference = await Process.run(Platform.resolvedExecutable, [
          'test/compiler/fixtures/extensions.dart',
          group,
        ]);
        expect(reference.exitCode, 0, reason: reference.stderr.toString());
        expect(reference.stderr, isEmpty);
        expect(native.stdout, reference.stdout);
      }
      final expected = switch (group) {
        'access' => [
          '["implicitSetterStatement",3,4,null,[1,3,5]]',
          '["optionalRecordCall",true,null,null,[]]',
          '["nullablePattern",null,1,null,[26]]',
        ],
        'call' => [
          '["virtualGetter",3,11,null,[3,2,4]]',
          '["parenthesizedGetter",3,11,null,[2,3,4]]',
          '["nullAwareGetter",true,null,null,[]]',
          '["checkedReceiver","bad",null,"type",[8]]',
          '["realMember",null,13,null,[3,10]]',
          '["dynamicMiss",null,null,"method",[3]]',
        ],
        'tearoffs' => [
          '["capturedReceiver",3,113,null,[]]',
          '["cleanupTearOff",-1,null,"int:-1",[9]]',
          '["extractedNever",3,null,"int:3",[30]]',
          '["nullAwareTearOff",null,99,null,[]]',
          '["checkedExtraction","bad",null,"type",[3]]',
          '["boundedTearOffDefault",null,null,"type",[]]',
          '["genericIdentity",null,true,null,[]]',
        ],
        _ => [
          '["implicitSetterValue",3,4,null,[1,3,5]]',
          '["explicitIndexValue",3,4,null,[1,6,3,5]]',
          '["explicitIndexFailure",0,7,null,[1,2,3,5,8]]',
          '["explicitIndexFailure",1,null,"state",[-1,8]]',
          '["explicitIndexFailure",2,null,"state",[1,-2,8]]',
          '["explicitIndexFailure",3,null,"state",[1,2,-3,8]]',
          '["explicitIndexFailure",4,null,"type",[1,2,8]]',
          '["explicitIndexFailure",5,null,"type",[1,2,3,8]]',
          '["implicitSetterFailure",0,7,null,[1,3,5,8]]',
          '["implicitSetterFailure",1,null,"state",[-1,8]]',
          '["implicitSetterFailure",3,null,"state",[1,-3,8]]',
          '["implicitSetterFailure",5,null,"type",[1,3,8]]',
        ],
      };
      final observations = const LineSplitter().convert(
        native.stdout.toString(),
      );
      if (group == 'order') {
        // SDK assignment values have a separately documented ordering difference.
        expect(observations, expected);
      } else {
        expect(observations, containsAll(expected));
      }
    });
  }
}
