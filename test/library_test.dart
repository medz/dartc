import 'dart:io';

void run(String executable, List<String> arguments) {
  final result = Process.runSync(
    executable,
    arguments,
    environment: {'PATH': '/usr/bin:/bin'},
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
}

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  final temporary = Directory.systemTemp.createTempSync('dartc-library-');
  try {
    final host = File('${temporary.path}/host.c')
      ..writeAsStringSync(
        '#include <stdint.h>\n'
        'extern int64_t add(int64_t, int64_t);\n'
        'int main(void) { return add(20, 22) == 42 ? 0 : 1; }\n',
      );
    for (final kind in ['static', 'dylib']) {
      final suffix = kind == 'static' ? 'a' : 'dylib';
      final library = '${temporary.path}/libmath.$suffix';
      final options = [
        '$root/example/math.dart',
        '--emit',
        kind,
        '-o',
        library,
        '--export',
        'add',
      ];
      if (args.isEmpty) {
        run(Platform.resolvedExecutable, ['$root/bin/dartc.dart', ...options]);
      } else {
        run(File(args.single).absolute.path, options);
      }
      final executable = '${temporary.path}/host-$kind';
      run('/usr/bin/clang', [
        host.path,
        library,
        '-Wl,-rpath,@loader_path',
        '-o',
        executable,
      ]);
      run(executable, []);
    }
    stdout.writeln(
      'C calls the FFI export through static and dynamic linkage.',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
