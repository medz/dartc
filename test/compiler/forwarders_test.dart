@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['typed', 'results', 'covariance', 'private']) {
    test('native forwarders preserve $group contracts', () async {
      final reference = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/forwarders.dart',
        group,
      ]);
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_forwarders')
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
        'typed' => [
          '["forwardInheritance",0,10,null,[90]]',
          '["forwardInheritance",1,10,null,[90]]',
          '["forwardInheritance",3,40,null,[40]]',
          '["forwardVoid",0,7,null,[90]]',
          '["forwardVoid",6,null,"type",[90]]',
          '["forwardFailures",[0,"bad"],null,"type",[2]]',
          '["forwardSuperOrder",null,"11:11:12:3:6",null,[]]',
        ],
        'results' => [
          '["forwardResult",[0,3],[1,"record"],null,[]]',
          '["forwardResult",[2,2],null,"type",[]]',
          '["forwardResult",[3,0],null,"type",[]]',
          '["forwardResult",[4,1],null,"type",[]]',
          '["forwardResult",[5,3],[1,"record"],null,[]]',
        ],
        'covariance' => [
          '["forwardCovariance",[1,1.5],null,"type",[]]',
          '["sourceCovariance",[0,7],true,null,[]]',
          '["sourceCovariance",[1,"bad"],null,"type",[]]',
          '["ownSourceCovariance",[1,7],8,null,[]]',
          '["sourceCovariance",[9,7],null,"type",[]]',
        ],
        _ => [
          '["privateForms",[1,0,7],null,"method",[]]',
          '["privateForms",[1,1,"bad"],null,"type",[]]',
          '["privateOwn",null,123,null,[]]',
          '["privateErrorFactory",0,true,null,[]]',
          '["privateErrorFactory",2,false,null,[]]',
          '["privatePublicBody",null,19,null,[]]',
        ],
      };
      expect(
        const LineSplitter().convert(native.stdout.toString()),
        containsAll(expected),
      );
    });
  }
}
