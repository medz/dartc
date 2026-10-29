import 'dart:io';

import '../lib/src/source.dart';

ProcessResult run(
  String executable,
  List<String> arguments, {
  String? directory,
  bool native = false,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: directory,
    environment: native ? {'PATH': '/usr/bin:/bin'} : null,
    includeParentEnvironment: !native,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  if (args.length != 2 || args[0] != '--compiler') {
    stderr.writeln(
      'Usage: dart tool/package_release.dart --compiler <native dartc>',
    );
    exit(64);
  }
  final compiler = File(args[1]).absolute;
  final os = Platform.operatingSystem;
  final machine = (run('/usr/bin/uname', ['-m']).stdout as String).trim();
  final architecture = switch (machine) {
    'arm64' || 'aarch64' => 'arm64',
    'x86_64' when os == 'linux' => 'x64',
    _ => throw StateError('Unsupported release host: $os/$machine'),
  };
  if (os != 'macos' && os != 'linux')
    throw StateError('Unsupported release OS: $os');
  final version = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(File('$root/pubspec.yaml').readAsStringSync())!.group(1)!;
  final name = 'dartc-$version-$os-$architecture';
  final output = Directory('$root/build/release')..createSync(recursive: true);
  final temporary = Directory.systemTemp.createTempSync('dartc-release-');
  try {
    final bundle = Directory('${temporary.path}/$name')..createSync();
    final binary = File('${bundle.path}/bin/dartc');
    binary.parent.createSync();
    compiler.copySync(binary.path);
    run('/bin/chmod', ['755', binary.path]);
    final runtime = File('$root/lib/src/runtime.dart').uri.toString();
    final sources = collectSources(
      runtime,
      runtime,
      null,
      os == 'macos' ? 0 : 1,
    );
    for (final source in sources.files) {
      if (!source.path.startsWith('$root/')) {
        throw StateError(
          'Native release dependency is outside the checkout: ${source.path}',
        );
      }
      final relative = source.path.substring(root.length + 1);
      final destination = File('${bundle.path}/$relative');
      destination.parent.createSync(recursive: true);
      File(source.path).copySync(destination.path);
    }
    File('$root/LICENSE').copySync('${bundle.path}/LICENSE');
    File('${bundle.path}/README.md').writeAsStringSync('''# dartc $version

Native Dart compiler for $os $architecture. This is an early preview release.

Keep bin/ and lib/ together. Add this bundle's bin directory to PATH,
then compile with `dartc hello.dart -o hello` and run `./hello`.
The compiler and output executables do not need the Dart SDK or VM.

Language implementation is in progress; see the specification tracker for
supported behavior and remaining gaps. Runtime sources must match the bundled compiler.

Usage: https://github.com/medz/dartc/tree/v$version
Compatibility: https://github.com/medz/dartc/tree/v$version/specs
License: MIT (included).
''');
    final archive = File('${temporary.path}/$name.tar.gz');
    run('/usr/bin/tar', [
      if (os == 'macos') '--no-mac-metadata',
      '-czf',
      archive.path,
      '-C',
      temporary.path,
      name,
    ]);

    // Validate the shipped files, with no checkout or SDK path available.
    final unpacked = Directory('${temporary.path}/unpacked')..createSync();
    run('/usr/bin/tar', ['-xzf', archive.path, '-C', unpacked.path]);
    final installed = '${unpacked.path}/$name';
    final work = Directory('${temporary.path}/project')..createSync();
    File('${work.path}/hello.dart').writeAsStringSync('''
void main() {
  try {
    throw 'release';
  } on String catch (value, trace) {
    if (value != 'release' || trace.toString().indexOf('main') < 0) {
      print('release failed');
      return;
    }
  }
  final trace = StackTrace.current.toString();
  if (trace.indexOf('main') < 0 || double.parse('1.25') != 1.25) {
    print('release failed');
    return;
  }
  print('release ok');
}
''');
    final aliases = Directory('${temporary.path}/aliases')..createSync();
    Link('${aliases.path}/dartc').createSync('$installed/bin/dartc');
    for (final command in [
      ['$installed/bin/dartc'],
      ['/usr/bin/env', 'PATH=$installed/bin:/usr/bin:/bin', 'dartc'],
      ['/usr/bin/env', 'PATH=${aliases.path}:/usr/bin:/bin', 'dartc'],
    ]) {
      run(
        command.first,
        [...command.skip(1), 'hello.dart', '-o', 'hello'],
        directory: work.path,
        native: true,
      );
      final result = run(
        '${work.path}/hello',
        [],
        directory: work.path,
        native: true,
      );
      if (result.stdout != 'release ok\n') {
        throw StateError(
          'Extracted native compiler produced unexpected output.',
        );
      }
    }
    final hash = run(os == 'macos' ? '/usr/bin/shasum' : '/usr/bin/sha256sum', [
      if (os == 'macos') ...['-a', '256'],
      archive.path,
    ]);
    final digest = (hash.stdout as String).split(RegExp(r'\s+')).first;
    final published = File('${output.path}/$name.tar.gz');
    archive.copySync(published.path);
    File('${published.path}.sha256')
        .writeAsStringSync('$digest  $name.tar.gz\n');
    stdout.writeln(published.path);
    stdout.writeln(
      'Extracted native compiler: direct, PATH and symlink checks passed.',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
