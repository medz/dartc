import 'dart:convert';
import 'dart:io';

ProcessResult run(
  String executable,
  List<String> arguments, {
  int expectedExit = 0,
  String? directory,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: directory,
    environment: {'PATH': '/usr/bin:/bin', 'TMPDIR': Directory.systemTemp.path},
    includeParentEnvironment: false,
  );
  if (result.exitCode != expectedExit) {
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
  final sharedSuffix = Platform.isMacOS ? 'dylib' : 'so';
  String cCompiler(String language) => Platform.isMacOS
      ? '/usr/bin/clang'
      : language == 'c'
      ? '/usr/bin/gcc'
      : '/usr/bin/g++';
  final build = Directory('$root/build')..createSync(recursive: true);
  final temporary = build.createTempSync('library-');
  var succeeded = false;
  try {
    final packages = File('${temporary.path}/package_config.json')
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'dartc',
              'rootUri': Directory(root).uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
          ],
        }),
      );
    ProcessResult compile(
      String source,
      List<String> options, {
      int expectedExit = 0,
      String? directory,
    }) {
      final arguments = [
        source,
        '--packages',
        packages.path,
        '--std',
        '$root/lib/src/runtime.dart',
        ...options,
      ];
      if (args.isEmpty) {
        return run(
          Platform.resolvedExecutable,
          ['$root/bin/dartc.dart', ...arguments],
          expectedExit: expectedExit,
          directory: directory,
        );
      } else {
        return run(
          File(args.single).absolute.path,
          arguments,
          expectedExit: expectedExit,
          directory: directory,
        );
      }
    }

    void link(String source, String library, String output, String language) {
      run(cCompiler(language), [
        '-x',
        language,
        language == 'c' ? '-std=c11' : '-std=c++17',
        '-Wall',
        '-Wextra',
        '-Werror',
        source,
        '-x',
        'none',
        library,
        Platform.isMacOS ? '-Wl,-rpath,@loader_path' : r'-Wl,-rpath,$ORIGIN',
        '-o',
        output,
      ]);
    }

    final wide = File('${temporary.path}/wide.dart')
      ..writeAsStringSync('''
import 'dart:ffi';
import 'package:dartc/export.dart';
typedef Wide = Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64);
@Export<Wide>(symbol: 'blend')
int blendImpl(int a, int b, int c, int d, int e, int f, int g, int h) {
  if (a == 0) return b + c * 2 + d * 3 + e * 4 + f * 5 + g * 6 + h * 7;
  return blendImpl(a - 1, b, c, d, e, f, g, h) + h;
}
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
#include "libmath.h"
int main(void) { return check($binding); }
''');
      for (final kind in ['object', 'static', 'dylib']) {
        final suffix = switch (kind) {
          'object' => 'o',
          'static' => 'a',
          _ => sharedSuffix,
        };
        final library = '${directory.path}/libmath.$suffix';
        compile(binding == 'add' ? '$root/example/math.dart' : wide.path, [
          '--emit',
          kind,
          '-o',
          library,
        ]);
        for (final language in ['c', 'c++']) {
          link(
            host.path,
            library,
            '${directory.path}/host-$kind-$language',
            language,
          );
        }
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
      run(cCompiler('c'), [
        '-std=c11',
        '-Wall',
        '-Wextra',
        '-Werror',
        loader.path,
        if (Platform.isLinux) '-ldl',
        '-o',
        '${directory.path}/loader',
      ]);
      final moved = directory.renameSync(
        '${temporary.path}/relocated $binding',
      );
      for (final kind in ['object', 'static', 'dylib']) {
        for (final language in ['c', 'c++']) {
          run('${moved.path}/host-$kind-$language', []);
        }
      }
      run('${moved.path}/loader', ['${moved.path}/libmath.$sharedSuffix']);
    }

    {
      final directory = Directory('${temporary.path}/abi')..createSync();
      final host = File('$root/test/fixtures/native_library.c')
          .copySync('${directory.path}/host.c');
      for (final kind in ['object', 'static', 'dylib']) {
        final suffix = switch (kind) {
          'object' => 'o',
          'static' => 'a',
          _ => sharedSuffix,
        };
        final library = '${directory.path}/native_library.$suffix';
        compile('$root/test/fixtures/native_library.dart', [
          '--emit',
          kind,
          '-o',
          library,
          '--header',
          '${directory.path}/native_library.h',
        ]);
        for (final language in ['c', 'c++']) {
          final executable = '${directory.path}/host-$kind-$language';
          link(host.path, library, executable, language);
          run(executable, []);
        }
      }
    }

    final namesSource = File('${temporary.path}/库🙂.dart')
      ..writeAsStringSync('''
import 'dart:ffi';
import 'package:dartc/export.dart';
${List.generate(300, (index) => 299 - index).map((index) => "@Export<Int64 Function()>(symbol: 'e$index') int f$index() => $index;").join('\n')}
@Export<Int64 Function()>(symbol: '加🙂') int unicode() => 300;
''');
    final namesLibrary = '${temporary.path}/库🙂.$sharedSuffix';
    compile(namesSource.path, ['--emit', 'dylib']);
    final namesLoader = File('${temporary.path}/names.c')
      ..writeAsStringSync('''
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
int main(int argc, char** argv) {
  if (argc != 2) return 1;
  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) { fprintf(stderr, "%s\\n", dlerror()); return 2; }
  for (int i = 0; i < 300; ++i) {
    char name[16]; snprintf(name, sizeof(name), "e%d", i);
    int64_t (*call)(void) = (int64_t (*)(void)) dlsym(library, name);
    if (call == NULL || call() != i) return 3;
  }
  int64_t (*call)(void) = (int64_t (*)(void)) dlsym(library, "加🙂");
  if (call == NULL || call() != 300) return 4;
  return dlclose(library) == 0 ? 0 : 5;
}
''');
    final namesExecutable = '${temporary.path}/names';
    run(cCompiler('c'), [
      '-std=c11',
      '-Wall',
      '-Wextra',
      '-Werror',
      namesLoader.path,
      if (Platform.isLinux) '-ldl',
      '-o',
      namesExecutable,
    ]);
    run(namesExecutable, [namesLibrary]);

    final constant = File('${temporary.path}/constant.dart')
      ..writeAsStringSync('''
import 'dart:ffi';
import 'package:dartc/export.dart';
@Export<Int64>()
const int answer = 42;
''');
    final constantHost = File('${temporary.path}/constant.c')
      ..writeAsStringSync('''
#include "constant.h"
int main(void) { return answer == 42 ? 0 : 1; }
''');
    for (final kind in ['object', 'static', 'dylib']) {
      final library = '${temporary.path}/constant.$kind';
      compile(constant.path, ['--emit', kind, '-o', library]);
      for (final language in ['c', 'c++']) {
        final executable = '${temporary.path}/constant-$kind-$language';
        link(constantHost.path, library, executable, language);
        run(executable, []);
      }
    }

    {
      final directory = Directory('${temporary.path}/paths')..createSync();
      Directory('${directory.path}/sub').createSync();
      final input = File('${directory.path}/main.dart')
        ..writeAsStringSync('''
import 'dart:ffi';
import 'package:dartc/export.dart';
import 'dep%25%23%3F%F0%9F%99%82.h';
part 'part.dart';
@Export<Int64 Function(Int64)>()
int add(int value) => value + left + right;
void main() { print(add(0)); }
''');
      final dependency = File('${directory.path}/dep%#?🙂.h')
        ..writeAsStringSync('const left = 20;');
      final part = File('${directory.path}/part.dart')
        ..writeAsStringSync("part of 'main.dart'; const right = 22;");
      final output = File('${directory.path}/artifact')
        ..writeAsStringSync('previous binary');
      final header = File('${directory.path}/artifact.h')
        ..writeAsStringSync('previous header');
      final originals = {
        for (final file in [input, dependency, part, packages, output, header])
          file.path: base64Encode(file.readAsBytesSync()),
      };
      for (final kind in ['exe', 'object', 'static', 'dylib']) {
        final targets = [
          'sub/../main.dart',
          '${directory.path}//dep%#?🙂.h',
          './part.dart',
          packages.path,
        ];
        final options = [
          for (final target in targets)
            [
              '-o',
              target,
              if (kind != 'exe') ...['--header', header.path],
            ],
          if (kind != 'exe') ...[
            for (final target in targets)
              ['-o', output.path, '--header', target],
            ['-o', output.path, '--header', 'sub/../artifact'],
            ['-o', 'dep%#?🙂.o'], // The default header is an imported source.
          ],
        ];
        for (final option in options) {
          final result = compile(
            'main.dart',
            ['--emit', kind, ...option],
            expectedExit: 64,
            directory: directory.path,
          );
          if (result.stdout != '' || result.stderr == '')
            throw StateError('Output path errors must use stderr.');
          for (final original in originals.entries)
            if (base64Encode(File(original.key).readAsBytesSync()) !=
                original.value)
              throw StateError('Rejected output changed ${original.key}.');
        }
      }
      // Outputs are file paths, so a literal file: prefix is not a URI.
      compile('main.dart', ['-o', 'file:main.dart'], directory: directory.path);
      if (run('${directory.path}/file:main.dart', []).stdout != '42\n')
        throw StateError('Literal output path produced an invalid program.');
      final host = File('${directory.path}/host.c')
        ..writeAsStringSync('''
#include "file:main.dart"
int main(void) { return add(0) == 42 ? 0 : 1; }
''');
      for (final kind in ['object', 'static', 'dylib']) {
        final library = '${directory.path}/file:artifact.$kind';
        compile('main.dart', [
          '--emit',
          kind,
          '-o',
          library,
          '--header',
          'file:main.dart',
        ], directory: directory.path);
        for (final language in ['c', 'c++']) {
          final executable = '${directory.path}/host-$kind-$language';
          link(host.path, library, executable, language);
          run(executable, []);
        }
      }
    }

    final unsupported = <String, String>{
      'division': '@Export<Int64 Function(Int64, Int64)>() int divide(int a, int b) => a ~/ b;',
      'indirect': 'int helper(int a, int b) => a ~/ b; @Export<Int64 Function(Int64, Int64)>() int divide(int a, int b) => helper(a, b);',
      'global':
          'int state = 0; @Export<Int64 Function()>() int next() => ++state;',
      'throw': '@Export<Int64 Function()>() int fail() => throw 42;',
      'allocation':
          '@Export<Int64 Function(Int64)>() int read(int x) => <int>[x][x];',
    };
    for (final entry in unsupported.entries) {
      final source = File('${temporary.path}/${entry.key}.dart')
        ..writeAsStringSync(
          "import 'dart:ffi'; import 'package:dartc/export.dart'; ${entry.value}",
        );
      final output = '${temporary.path}/${entry.key}.dylib';
      compile(source.path, ['--emit', 'dylib', '-o', output], expectedExit: 1);
      if (File(output).existsSync() ||
          File('${temporary.path}/${entry.key}.h').existsSync()) {
        throw StateError(
          'Unsupported runtime boundary produced library files.',
        );
      }
    }
    stdout.writeln(
      'Generated headers, C/C++ calls, scalar data and relocated libraries passed.',
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
