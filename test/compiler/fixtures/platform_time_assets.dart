import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/compiler.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

Future<void> buildPlatformTime(Target target) async {
  final result =
      await Compiler(
        target,
        resources: _Sources(await SdkSources.load()),
      ).compile([
        '/__dartc__/test/compiler/fixtures/platform_time.dart',
      ], output: const .executable());
  await result.write(NativeAssets(target).file('compiler/entry_platform_time'));
}

final class _Sources(final SdkSources sdk) extends SdkSources {
  final _fixtures = {
    for (final name in ['platform_time.dart', 'platform_time_cases.dart'])
      'test/compiler/fixtures/$name': File('test/compiler/fixtures/$name')
          .readAsBytesSync(),
  };
  @override
  Iterable<String> get paths => [...sdk.paths, ..._fixtures.keys];
  @override
  bool contains(String path) =>
      _fixtures.containsKey(path) || sdk.contains(path);
  @override
  int? length(String path) => _fixtures[path]?.length ?? sdk.length(path);
  @override
  Uint8List read(String path) => _fixtures[path] ?? sdk.read(path);
}
