@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'private symbols retain library identity across constants and calls',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_symbols')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(result.stdout, '''local:true:true
foreign:false:false
constructor:false:false
public:true:true
folded:false:2:true
defaults:true:true
constructors:true:true
covariance:true
nested:true:true
collections:1:2:3:3
hash:true:true:true
patterns:1:2:3
map-pattern:3
invocations:true:true:true
qualified:true:true
''');
    },
  );
}
