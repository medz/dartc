import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test('validates an explicit SDK without installing or copying it', () {
    final sdk = DartSdk.current();
    expect(sdk.version, isNotEmpty);
    expect(
      File.fromUri(sdk.libraries.uri.resolve('core/core.dart')).existsSync(),
      isTrue,
    );
    expect(() => DartSdk.at('test/compiler/fixtures'), throwsArgumentError);
  });

  test('resolves explicit roots, executables and the current SDK', () async {
    final sdk = DartSdk.current(), resolver = SdkResolver();
    for (final selected in [
      await resolver.resolve(),
      await resolver.resolve(source: sdk.directory.path),
      await resolver.resolve(source: Platform.resolvedExecutable),
    ]) {
      expect(selected.directory.path, sdk.directory.path);
      expect(selected.version, DartSdk.supportedVersion);
    }
  });

  test('an invalid explicit source never falls back', () async {
    final resolver = SdkResolver();
    for (final source in [
      '',
      'test/compiler/fixtures',
      'dartc-missing-sdk-command',
    ]) {
      await expectLater(resolver.resolve(source: source), throwsArgumentError);
    }
  });

  test('checks the source version before accepting an explicit SDK', () async {
    final root = Directory('build/test/sdk')..createSync(recursive: true);
    final work = root.createTempSync('version-');
    addTearDown(() => work.deleteSync(recursive: true));
    final sdk = DartSdk.current();
    for (final name in [
      'version',
      'lib/libraries.json',
      'lib/core/core.dart',
      'lib/_internal/allowed_experiments.json',
      'lib/_internal/sdk_library_metadata/lib/libraries.dart',
    ]) {
      final destination = File.fromUri(work.uri.resolve(name));
      destination.parent.createSync(recursive: true);
      File.fromUri(sdk.directory.uri.resolve(name)).copySync(destination.path);
    }
    final version = File.fromUri(work.uri.resolve('version'));
    version.writeAsStringSync('3.14.0');
    await expectLater(
      SdkResolver().resolve(source: work.path),
      throwsUnsupportedError,
    );
    version.writeAsStringSync('');
    expect(() => DartSdk.at(work.path), throwsFormatException);
  });

  test(
    'queries a Dart wrapper without guessing its installation layout',
    () async {
      final root = Directory('build/test/sdk')..createSync(recursive: true);
      final work = root.createTempSync('wrapper with spaces-');
      addTearDown(() => work.deleteSync(recursive: true));
      final wrapper = File('test/sdk/fixtures/dart-wrapper')
          .copySync('${work.path}/dart-wrapper');
      Link('${work.path}/dart-link').createSync(Platform.resolvedExecutable);
      expect((await Process.run('chmod', ['+x', wrapper.path])).exitCode, 0);
      final sdk = await SdkResolver().resolve(source: wrapper.path);
      expect(sdk.directory.path, DartSdk.current().directory.path);
    },
    testOn: 'mac-os || linux',
  );
}
