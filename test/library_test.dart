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
  final build = Directory('$root/build')..createSync(recursive: true);
  final temporary = build.createTempSync('library-');
  var succeeded = false;
  try {
    final wide = File('${temporary.path}/wide.dart')
      ..writeAsStringSync('''
import 'dart:ffi';
typedef Wide = Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64);
int blendImpl(int a, int b, int c, int d, int e, int f, int g, int h) {
  if (a == 0) return b + c * 2 + d * 3 + e * 4 + f * 5 + g * 6 + h * 7;
  return blendImpl(a - 1, b, c, d, e, f, g, h) + h;
}
final blend = Pointer.fromFunction<Wide>(blendImpl, 0);
''');
    for (final binding in ['add', 'blend']) {
      final caller = binding == 'add'
          ? 'extern int64_t add(int64_t, int64_t);\n'
                'int main(void) { return add(20, 22) == 42 ? 0 : 1; }\n'
          : 'extern int64_t blend(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);\n'
                'int main(void) { return blend(3, -2, 3, 4, 5, 6, 7, INT64_C(4294967296)) == INT64_C(42949673068) ? 0 : 1; }\n';
      final host = File('${temporary.path}/host.c')
        ..writeAsStringSync('#include <stdint.h>\n$caller');
      for (final kind in ['object', 'static', 'dylib']) {
        final suffix = switch (kind) {
          'object' => 'o',
          'static' => 'a',
          _ => 'dylib',
        };
        final library = '${temporary.path}/libmath.$suffix';
        final options = [
          binding == 'add' ? '$root/example/math.dart' : wide.path,
          '--emit',
          kind,
          '-o',
          library,
          '--export',
          binding,
        ];
        if (args.isEmpty) {
          run(Platform.resolvedExecutable, [
            '$root/bin/dartc.dart',
            ...options,
          ]);
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
    }
    stdout.writeln(
      'C calls two- and eight-argument FFI exports through object, static and dynamic linkage.',
    );
    succeeded = true;
  } finally {
    if (succeeded) {
      temporary.deleteSync(recursive: true);
    } else {
      stderr.writeln('Library failure preserved at ${temporary.path}');
    }
  }
}
