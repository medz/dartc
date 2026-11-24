@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(6)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/new_compiler.dart';

const _library = r'''
import 'dart:async';
import 'dart:ffi';
import 'package:dartc/interop.dart';
final class Point extends Struct { @Int32() external int x; @Int32() external int y; }
final class Big extends Struct { @Int64() external int a, b, c; @Array(2, 2) external Array<Array<Uint8>> grid; external Point at; external Pointer<Big> next; }
final class Any extends Union { @Double() external double d; @Float() external double f; }
int _count = 0;
final List<String> _log = [];
@Export<Int64 Function(Int64, Int64)>(symbol: 'math_add') int add(int left, int right) => left + right;
@Export<Int32 Function(Int8, Float, Double, Bool, Uint16)>() int mixed(int a, double b, double c, bool d, int e) => (a + b + c + (d ? 1 : 0) + e).toInt();
@Export<Double Function(Float)>() double half(double x) => x / 2;
@Export<Void Function(Pointer<Uint8>)>(symbol: 'log_text') void logText(Pointer<Uint8> p) { var s = ''; for (var i = 0; p[i] != 0; i++) s += String.fromCharCode(p[i]); _log.add(s); print('logged $s ${_log.length}'); }
@Export<Point Function(Point, Int32)>(symbol: 'point_move') Point movePoint(Point p, int by) => Struct.create<Point>()..x = p.x + by..y = p.y - by;
@Export<Big Function(Big)>(symbol: 'big_next') Big nextBig(Big b) { final r = Struct.create<Big>()..a = b.c..b = b.a..c = b.b..at = b.at..next = b.next; r.grid[1][0] = b.grid[0][1] + 1; return r; }
@Export<Bool Function(Pointer<NativeFunction<Int32 Function(Int32)>>, Int32)>() bool calls(Pointer<NativeFunction<Int32 Function(Int32)>> f, int x) { final g = f.asFunction<int Function(int)>(); return g(x) + g(x + 1) > 10; }
@Export<Int32 Function()>() int counted() { final l = [for (var i = 0; i < 60; i++) "x$i"]; return ++_count + l.length; }
@Export<Void Function(Int32)>() void later(int n) { scheduleMicrotask(() => print('later $n')); Timer(Duration(milliseconds: 5), () => print('timer $n')); print('now $n'); }
@Export<Any Function(Any)>() Any any(Any a) => Union.create<Any>()..d = a.d * 2;
@Export<Void Function()>() void fails() => throw StateError('bad');
@Export<Int32 Function(Int32)>() int depth(int n) => n <= 0 ? 0 : 1 + depth(n - 1);
''';

const _main = r'''
#include "lib.h"
#include <stdio.h>
#include <string.h>
static int32_t twice(int32_t x) { return x * 2 + counted() - counted(); }
int main(int argc, char **argv) {
  printf("%lld\n", (long long)math_add(40, 2));
  printf("%d\n", mixed(-3, 1.5f, 2.5, true, 65535));
  printf("%f\n", half(3.0f));
  log_text((uint8_t *)"hi"); log_text((uint8_t *)"there");
  struct Point p = { 3, 4 }; p = point_move(p, 10); printf("%d %d\n", p.x, p.y);
  struct Big b; memset(&b, 0, sizeof b); b.a = 1; b.b = 2; b.c = 3; b.grid[0][1] = 7; b.at = p; b.next = &b; b = big_next(b); printf("%lld %lld %lld %d %d %d\n", (long long)b.a, (long long)b.b, (long long)b.c, b.grid[1][0], b.at.x, b.next == &b);
  printf("%d %d\n", calls(twice, 1), calls(twice, 5));
  for (int i = 0; i < 20; i++) counted();
  printf("%d\n", counted());
  fflush(stdout); later(1); later(2);
  union Any a; a.d = 2.25; printf("%f\n", any(a).d);
  printf("%d\n", depth(2000));
  fflush(stdout);
  if (argc > 1) fails();
  return 0;
}
''';

const _expected = '''
logged hi 1
logged there 2
42
65537
1.500000
13 -6
3 1 2 8 13 1
0 1
89
now 1
later 1
timer 1
now 2
later 2
timer 2
4.500000
2000
''';

/// A directory with [files] that can use this package.
Directory _sources(Map<String, String> files) {
  final config = File('.dart_tool/package_config.json').readAsStringSync();
  return writeSources({
    ...files,
    '.dart_tool/package_config.json': config.replaceFirst(
      '"rootUri": "../"',
      '"rootUri": "${Directory.current.uri}"',
    ),
  });
}

void main() {
  for (final kind in LibraryKind.values) {
    for (final collectsAlways in [false, true]) {
      test('C uses a library: ${kind.name}, $collectsAlways', () async {
        final directory = _sources({'lib.dart': _library, 'main.c': _main});
        final path = '${directory.path}/lib.dart';
        final name = switch (kind) {
          .object => 'lib.o',
          .static => 'lib.a',
          .shared => 'lib.dylib',
        };
        final output = '${directory.path}/$name';
        final (:bytes, :header) = await compileLibrary(
          path,
          kind,
          name: output,
          collectsAlways: collectsAlways,
        );
        writeProgram(bytes, output);
        File('${directory.path}/lib.h').writeAsStringSync(header);
        ProcessResult run(String tool, List<String> arguments) =>
            Process.runSync(tool, arguments, workingDirectory: directory.path);
        for (final (compiler, extra) in [
          ('clang', const <String>[]),
          ('clang++', const ['-x', 'c++', 'main.c', '-x', 'none']),
        ]) {
          final built = run(compiler, [
            '-Wall',
            '-o',
            'main',
            if (extra.isEmpty) 'main.c' else ...extra,
            name,
          ]);
          expect(built.exitCode, 0, reason: '${built.stderr}');
          final result = run('${directory.path}/main', const []);
          expect(result.stdout, _expected, reason: '${result.stderr}');
          expect(result.exitCode, 0);
        }
        final failed = run('${directory.path}/main', const ['x']);
        expect(failed.stderr, contains('Bad state: bad'));
        expect(failed.exitCode, -ProcessSignal.sigabrt.signalNumber);
      }, skip: skipExecution);
    }
  }

  test('the official runtime loads a library', () async {
    final directory = _sources({'lib.dart': _library});
    final output = '${directory.path}/lib.dylib';
    final made = await compileLibrary(
      '${directory.path}/lib.dart',
      .shared,
      name: output,
    );
    writeProgram(made.bytes, output);
    File('${directory.path}/main.dart').writeAsStringSync('''
import 'dart:ffi';
void main() {
  final library = DynamicLibrary.open('$output');
  final add = library.lookupFunction<Int64 Function(Int64, Int64),
      int Function(int, int)>('math_add');
  print(add(20, 22));
  final later = library.lookupFunction<Void Function(Int32),
      void Function(int)>('later');
  later(3);
}
''');
    final result = await Process.run('$hostSdk/bin/dart', [
      'run',
      '${directory.path}/main.dart',
    ]);
    expect('${result.stdout}'.split('\n')..sort(), [
      '',
      '42',
      'later 3',
      'now 3',
      'timer 3',
    ], reason: '${result.stderr}');
  }, skip: skipExecution);

  group('problems', () {
    void reports(String source, String problem) => test(problem, () async {
      final directory = _sources({
        'lib.dart':
            "import 'dart:ffi'; import 'package:dartc/interop.dart';\n$source",
      });
      await expectLater(
        compileLibrary('${directory.path}/lib.dart', .object, name: 'lib.o'),
        throwsA(
          isA<CompileFailure>().having(
            (failure) => '$failure',
            'text',
            contains('lib.dart:$problem'),
          ),
        ),
      );
    });

    reports('void f() {}', '1:1: The library exports no functions.');
    const what = 'Not supported yet:';
    reports(
      '@Export<Void Function(Int32)>() void f([int a = 1]) {}',
      '2:1: $what exporting this kind of function.',
    );
    reports(
      '@Export<Void Function(Int32)>() void f(double a) {}',
      '2:1: $what exporting a parameter of type double.',
    );
    reports(
      '@Export<Int32 Function()>() Future<int> f() async => 1;',
      '2:1: $what exporting this kind of function.',
    );
    reports(
      "@Export<Void Function()>(symbol: 'a b') void f() {}",
      "2:1: $what exporting what is called 'a b'.",
    );
    reports(
      "@Export<Void Function()>(symbol: 'g') void f() {}\n"
          '@Export<Void Function()>() void g() {}',
      "3:1: $what exporting 'g' twice.",
    );
    reports(
      'class A { @Export<Void Function()>() static void f() {} }',
      '2:1: $what exporting members.',
    );
  });
}
