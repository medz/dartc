@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'standalone dartc compiles with bundled SDK sources and no Dart command',
    () async {
      final assets = NativeAssets(Target.host());
      final work = Directory('build/test/compiler').absolute
          .createTempSync('standalone-');
      addTearDown(() => work.delete(recursive: true));
      final input = Directory('build/test/compiler/input').absolute;
      for (final file in input.listSync(recursive: true).whereType<File>()) {
        final name = file.uri.pathSegments
            .skip(input.uri.pathSegments.length - 1)
            .join('/');
        final copy = File.fromUri(work.uri.resolve(name));
        copy.parent.createSync(recursive: true);
        file.copySync(copy.path);
      }
      final output = File.fromUri(
        work.uri.resolve(
          assets.library('compiler/standalone').uri.pathSegments.last,
        ),
      );
      final result = await Process.run(
        assets.file('compiler/dartc').absolute.path,
        ['entry.dart', '-o', output.path, '--kind', 'shared'],
        workingDirectory: work.path,
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final client = await Process.run(
        assets.file('compiler/client').absolute.path,
        [output.path],
        workingDirectory: work.path,
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(client.exitCode, 0, reason: '${client.stdout}${client.stderr}');
      final executable = File.fromUri(work.uri.resolve('program'));
      final compile = await Process.run(
        assets.file('compiler/dartc').absolute.path,
        ['program.dart', '-o', executable.path, '--kind', 'exe'],
        workingDirectory: work.path,
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');
      final run = await Process.run(
        executable.path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final apiOutput = File.fromUri(work.uri.resolve('api-program'));
      final api = await Process.run(
        assets.file('compiler/compiler-client').absolute.path,
        [
          assets.file('compiler/sources.zip').absolute.path,
          '${work.path}/program.dart',
          apiOutput.path,
        ],
        workingDirectory: work.path,
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(api.exitCode, 0, reason: '${api.stdout}${api.stderr}');
      final apiRun = await Process.run(
        apiOutput.path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(apiRun.exitCode, 0, reason: '${apiRun.stdout}${apiRun.stderr}');
    },
  );
}
