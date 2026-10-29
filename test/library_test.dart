import 'dart:io';

void run(String executable, List<String> arguments) {
  final result = Process.runSync(
    executable,
    arguments,
    environment: {'PATH': '/usr/bin:/bin', 'TMPDIR': Directory.systemTemp.path},
    includeParentEnvironment: false,
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
      final directory = Directory('${temporary.path}/$binding')..createSync();
      final parameters = List.filled(
        binding == 'add' ? 2 : 8,
        'int64_t',
      ).join(', ');
      final checks = binding == 'add'
          ? '''
  if (call(20, 22) != 42) return 1;
  if (call(INT64_MIN, 0) != INT64_MIN) return 2;
  if (call(INT64_MAX, 0) != INT64_MAX) return 3;
  if (call(-INT64_C(4294967296), INT64_C(4294967338)) != 42) return 4;
'''
          : '''
  if (call(3, -2, 3, 4, 5, 6, 7, INT64_C(4294967296)) != INT64_C(42949673068)) return 1;
  if (call(2, -2, 3, 4, 5, 6, 7, -INT64_C(4294967296)) != -INT64_C(38654705556)) return 2;
  if (call(0, 0, 0, 0, 0, 0, 0, 0) != 0) return 3;
''';
      final checker =
          '''
#include <stdint.h>
typedef int64_t Operation($parameters);
static int check(Operation* call) {
$checks
  return 0;
}
''';
      final host = File('${directory.path}/host.c')
        ..writeAsStringSync('''
$checker
extern Operation $binding;
int main(void) { return check($binding); }
''');
      for (final kind in ['object', 'static', 'dylib']) {
        final suffix = switch (kind) {
          'object' => 'o',
          'static' => 'a',
          _ => 'dylib',
        };
        final library = '${directory.path}/libmath.$suffix';
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
        final executable = '${directory.path}/host-$kind';
        run('/usr/bin/clang', [
          '-std=c11',
          '-Wall',
          '-Wextra',
          '-Werror',
          host.path,
          library,
          '-Wl,-rpath,@loader_path',
          '-o',
          executable,
        ]);
      }
      final loader = File('${directory.path}/loader.c')
        ..writeAsStringSync('''
#include <dlfcn.h>
#include <stdio.h>
$checker
int main(int argc, char** argv) {
  if (argc != 2) return 1;
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) {
    fprintf(stderr, "%s\\n", dlerror());
    return 1;
  }
  dlerror();
  Operation* call = (Operation*) dlsym(library, "$binding");
  const char* error = dlerror();
  if (error != NULL) {
    fprintf(stderr, "%s\\n", error);
    dlclose(library);
    return 1;
  }
  int result = check(call);
  if (dlclose(library) != 0) {
    fprintf(stderr, "%s\\n", dlerror());
    return 1;
  }
  return result;
}
''');
      run('/usr/bin/clang', [
        '-std=c11',
        '-Wall',
        '-Wextra',
        '-Werror',
        loader.path,
        '-o',
        '${directory.path}/loader',
      ]);
      final moved = directory.renameSync(
        '${temporary.path}/relocated $binding',
      );
      for (final kind in ['object', 'static', 'dylib']) {
        run('${moved.path}/host-$kind', []);
      }
      run('${moved.path}/loader', ['${moved.path}/libmath.dylib']);
    }
    stdout.writeln(
      'C calls two- and eight-argument FFI exports after relocation through '
      'object, static, dynamic and dlopen/dlsym linkage.',
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
