import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';

final class NativeAssets(final Target target) {
  /// A bench host test receives the freshly compiled fixture's asset directory.
  final Directory directory = Directory(
    Platform.environment['DARTC_TEST_NATIVE_ASSET_ROOT'] ??
        'build/test/$target',
  );

  File file(String name) => File.fromUri(directory.uri.resolve(name));

  File library(String name) =>
      file('$name.${target.operatingSystem == .macos ? 'dylib' : 'so'}');

  DynamicLibrary open(String name) {
    final asset = library(name);
    if (!asset.existsSync()) {
      throw StateError(
        'Missing ${asset.path}. Run dart run tool/build_test_assets.dart first.',
      );
    }
    return DynamicLibrary.open(asset.absolute.path);
  }
}
