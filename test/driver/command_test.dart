import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';

/// Runs the compiler with [arguments], given a directory with [files].
Future<({int code, String output, String errors, Directory directory})> run(
  List<String> Function(String directory) arguments, {
  Map<String, String> files = const {'main.dart': 'void main() {}'},
}) async {
  final directory = writeSources(files);
  final output = StringBuffer(), errors = StringBuffer();
  final code = await runCommand(
    arguments(directory.path),
    output: output,
    errors: errors,
    sdk: packagedSdkFiles,
  );
  return (
    code: code,
    output: '$output',
    errors: '$errors',
    directory: directory,
  );
}

void main() {
  void refuses(String name, List<String> arguments, Object message) =>
      test('$name is refused', () async {
        final result = await run((path) => [...arguments, '$path/main.dart']);
        expect(result.code, 64);
        expect(result.output, isEmpty);
        expect(result.errors, message);
        expect(result.directory.listSync(), hasLength(1));
      });

  refuses('no output', const [], startsWith('Usage: '));
  refuses('a second source', const ['a.dart', '-o', 'x'], startsWith('Usage'));
  refuses('an unknown option', const [
    '--fast',
    '-o',
    'x',
  ], startsWith('Unknown option: --fast\nUsage: '));
  refuses('an unknown kind', const [
    '--kind',
    'dll',
  ], 'Unknown kind of output: dll\n');
  refuses('an unknown target', const [
    '--target=amiga',
  ], 'Unknown target: amiga\n');
  refuses('a definition without a value', const [
    '-Dname',
  ], 'Expected name=value: name\n');
  refuses('a definition of what the compiler tells', const [
    '-Ddart.library.io=false',
  ], 'Only the compiler tells what dart.library.io is.\n');
  refuses('a header of a program', const [
    '--header',
    'x.h',
    '-o',
    'x',
  ], 'Only libraries have headers.\n');

  test('options need their values', () async {
    final result = await run((path) => ['$path/main.dart', '-o']);
    expect((result.code, result.errors), (64, 'Missing value for -o.\n'));
  });

  test('help is given', () async {
    final result = await run((_) => const ['-h']);
    expect((result.code, result.errors), (0, ''));
    expect(result.output, startsWith('Usage: '));
  });

  test('problems are reported, and nothing is written', () async {
    final result = await run(
      (path) => ['$path/main.dart', '-o', '$path/main'],
      files: const {'main.dart': 'void main() {\n  int x = "a";\n}'},
    );
    expect((result.code, result.output), (1, ''));
    expect(result.errors, contains('main.dart:2:11: '));
    expect(result.directory.listSync(), hasLength(1));
  });

  test('outputs that cannot be written are reported', () async {
    final result = await run((path) => ['$path/main.dart', '-o', '$path/a/b']);
    expect(result.code, 1);
    expect(result.errors, contains('a/b'));
  });

  test('programs know what is defined', () async {
    final result = await run(
      (path) => [
        '-Da=b=c',
        '--define',
        'n=12',
        '$path/main.dart',
        '--define=yes=true',
        '-Dnone.library.js_interop=true',
        '-Dnone.library.js_interop0=true',
        '-Dnone.library.js_util=123',
        '-D',
        r"odd='$x\é🙂",
        '-o',
        '$path/main',
      ],
      files: const {
        'main.dart': r'''
          import 'none.dart' if (b) 'other.dart' if (yes) 'yes.dart';
          void main() {
            print(const String.fromEnvironment('a'));
            print(const int.fromEnvironment('n'));
            print(const bool.fromEnvironment('yes'));
            print(const String.fromEnvironment('odd'));
            print(const String.fromEnvironment('none', defaultValue: 'x'));
            print(const bool.hasEnvironment('a'));
            print(const bool.fromEnvironment('dart.library.io'));
            print(const bool.fromEnvironment('dart.library.js_interop'));
            print(bool.fromEnvironment('dart.library.js_interop'));
            print(const String.fromEnvironment(
              /* availability */ 'dart.library.js_util', defaultValue: 'native',
            ));
            print(const int.fromEnvironment(
              /* availability */ 'dart.library.js_util', defaultValue: 42,
            ));
            print(const bool.fromEnvironment('dart.vm.product'));
            for (final name in ['a', 'n', 'yes', 'odd', 'none']) {
              print((
                bool.hasEnvironment(name),
                String.fromEnvironment(name),
                int.fromEnvironment(name, defaultValue: 3),
                bool.fromEnvironment(name),
              ));
            }
            print(value);
          }
        ''',
        'none.dart': 'const value = 0;',
        'other.dart': 'const value = 1;',
        'yes.dart': 'const value = 2;',
      },
    );
    expect((result.code, result.errors), (0, ''));
    final program = Process.runSync('${result.directory.path}/main', const []);
    expect(program.stderr, isEmpty);
    expect(program.stdout, r'''
b=c
12
true
'$x\é🙂
x
true
true
false
false
native
42
true
(true, b=c, 3, false)
(true, 12, 12, false)
(true, true, 3, true)
(true, '$x\é🙂, 3, false)
(false, , 3, false)
2
''');
  });

  test('libraries are made with their headers', () async {
    final config = File('.dart_tool/package_config.json')
        .readAsStringSync()
        .replaceFirst(
          '"rootUri": "../"',
          '"rootUri": "${Directory.current.uri}"',
        );
    for (final kind in LibraryKind.values) {
      final result = await run(
        (path) => [
          '$path/main.dart',
          '--kind=${kind.name}',
          '--header=$path/main.h',
          '--target',
          'linux-x64',
          '-o',
          '$path/out',
        ],
        files: {
          'main.dart': '''
            import 'dart:ffi';
            import 'package:dartc/interop.dart';
            @Export<Int64 Function(Int64)>()
            int twice(int n) => n * 2;
          ''',
          '.dart_tool/package_config.json': config,
        },
      );
      expect((result.code, result.errors), (0, ''), reason: '$kind');
      final header = File('${result.directory.path}/main.h');
      expect(header.readAsStringSync(), contains('twice'));
      expect(File('${result.directory.path}/out').lengthSync(), isPositive);
    }
  });

  test('assertions are checked if programs are compiled so', () async {
    const source = r'''
      class A {
        final int v;
        A(this.v) : assert(v > 0, 'v was $v'), assert(v < 100);
        A.b(int w) : assert(w > 2), v = w;
        const A.c(this.v) : assert(v != 7);
        const A.e(double d) : assert(d == 0.0, 'not zero'), v = 1;
        factory A.d(int x) { assert(x != 1); return A(x); }
      }
      class B extends A { B(super.v) : assert(v != 5, 'five'), super(); }
      extension type E(int i) { E.pos(this.i) : assert(i > 0); }
      int calls = 0;
      bool check(bool b) { calls++; return b; }
      String msg() { calls += 10; return 'lazy'; }
      void t(Object? Function() f) {
        try { f(); print('ok'); }
        on AssertionError catch (e) { print(e); print(e.message); }
        catch (e) { print(e); }
      }
      Future<void> main() async {
        t(() { assert(1 + 1 == 3); });
        t(() { assert(check(true), msg()); });
        t(() { assert(check(false), msg()); });
        t(() => A(0)); t(() => A(100)); t(() => A(5)); t(() => A.b(1));
        t(() => A.c(7)); t(() => A.e(calls + 1)); t(() => A.d(1)); t(() => B(5)); t(() => E.pos(0));
        t(() { dynamic d = 'x'; assert(d); });
        t(() { dynamic d = false; assert(d, null); });
        t(() { assert(  false  ,  'spaces'  ); });
        t(() { assert((() { print('in'); return true; })()); });
        t(() { assert(false, A(3).v); });
        t(() { assert(false, throw 'thrown'); });
        t(() { assert(
           1 >
             2, 'two lines'); });
        int x = 1; assert((x = 2) == 2); print(x);
        assert(await Future.value(true));
        t(() { assert([1].first == 1); print([].isEmpty); });
        print(calls);
        assert(x == 1, 'end');
      }
    ''';
    for (final checks in [true, false]) {
      final result = await run(
        (path) => [
          '$path/main.dart',
          '-o',
          '$path/main',
          if (checks) '--enable-asserts',
        ],
        files: const {'main.dart': source},
      );
      expect((result.code, result.errors), (0, ''));
      final path = result.directory.path;
      final official = Process.runSync('$hostSdk/bin/dart', [
        'run',
        if (checks) '--enable-asserts',
        '$path/main.dart',
      ]);
      final program = Process.runSync('$path/main', const []);
      expect(program.stdout, official.stdout);
      expect(program.stdout, isNotEmpty);
      // Traces of the stack, which follow, are not compared.
      String told(Object errors) => '$errors'.split('#0 ').first;
      expect(told(program.stderr), told(official.stderr));
      expect(program.exitCode, official.exitCode);
    }
  });

  test('the command works from the package', () {
    final directory = writeSources({
      'main.dart': "void main() => print('hi');",
    });
    final result = Process.runSync(Platform.resolvedExecutable, [
      'bin/dartc.dart',
      '${directory.path}/main.dart',
      '-o',
      '${directory.path}/main',
    ]);
    expect((result.exitCode, result.stdout, result.stderr), (0, '', ''));
    final program = Process.runSync('${directory.path}/main', const []);
    expect((program.exitCode, program.stdout), (0, 'hi\n'));
  });
}
