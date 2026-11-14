@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['storage', 'language', 'mixins']) {
    test('native enums preserve $group contracts', () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/enums.dart',
        group,
      ]);
      final native = await Process.run(
        NativeAssets(Target.host()).file('compiler/entry_enums').absolute.path,
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
        'storage' => [
          '7:first:0:Code.first:first',
          '-3:second:second:true:true:true:false:11:33',
          'name:missing',
        ],
        'language' => [
          '["enumIdentity",null,5331,null,[]]',
          '["enumValuesImmutable",null,3,null,[]]',
          '["enhancedConstructors",null,"2:base;5:named;9:redirect",null,[]]',
          '["genericEnumTypes",null,255,null,[]]',
          '["enhancedFactories",true,109,null,[]]',
          '["enumObjectPattern",1,105,null,[5]]',
          '["genericEnumChecks","x",10,null,[]]',
        ],
        _ => [
          '["labels",null,"0:a:mixed:1:mixed:0:Numbered.a:2",null,[]]',
          '["parameters",null,"5:six:true:true",null,[]]',
          '["mixinArgument",[5,false],5,null,[]]',
          '["mixinArgument",[5,true],5,null,[]]',
          '["mixinArgument",[2.5,false],null,"type",[]]',
          '["mixinArgument",[2.5,true],null,"type",[]]',
        ],
      };
      expect(
        const LineSplitter().convert(native.stdout.toString()),
        containsAll(expected),
      );
    });
  }
}
