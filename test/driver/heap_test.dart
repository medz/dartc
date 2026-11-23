@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/new_compiler.dart';

/// Runs [source], which must print `ok`, compiled and officially, giving the
/// most memory that the compiled program used in bytes.
Future<int> _run(String source, {bool collectsAlways = false}) async {
  final directory = writeSources({'main.dart': source});
  final official = await Process.run('$hostSdk/bin/dart', [
    'run',
    '${directory.path}/main.dart',
  ]);
  expect(official.stdout, 'ok\n', reason: '${official.stderr}');
  final program = '${directory.path}/program';
  final bytes = await compileProgram(
    '${directory.path}/main.dart',
    sdk: hostSdk,
    collectsAlways: collectsAlways,
  );
  writeProgram(bytes, program);
  final result = await Process.run('/usr/bin/time', ['-l', program]);
  expect(result.stdout, 'ok\n', reason: '${result.stderr}');
  expect(result.exitCode, 0);
  final line = '${result.stderr}'
      .split('\n')
      .singleWhere((line) => line.contains('maximum resident set size'));
  return int.parse(line.trim().split(' ').first);
}

const _megabyte = 1 << 20;

void main() {
  void limited(String name, int megabytes, String source) =>
      test(name, () async {
        expect(await _run(source), lessThan(megabytes * _megabyte));
      }, skip: skipExecution);

  // 320 MB of objects.
  limited('objects that are dropped are used again', 12, '''
    class P { int a = 1, b = 2, c = 3; }
    void main() {
      var sum = 0;
      for (var i = 0; i < 10000000; i++) { final p = P(); p.a = i; sum += p.b; }
      if (sum == 20000000) print('ok');
    }
  ''');

  limited('cycles are dropped', 12, '''
    class P { P? other; }
    void main() {
      for (var i = 0; i < 5000000; i++) {
        final a = P(), b = P();
        a.other = b; b.other = a;
      }
      print('ok');
    }
  ''');

  // 20 lists of 32 MB; they would overflow a recursive collector's stack.
  limited('long lists are kept, then dropped', 200, '''
    class Node { final int n; final Node? next; Node(this.n, this.next); }
    Node? list;
    int count() {
      var n = 0;
      var at = list;
      while (at != null) { n++; at = at.next; }
      return n;
    }
    void main() {
      for (var i = 0; i < 20; i++) {
        list = null;
        for (var j = 0; j < 1000000; j++) { list = Node(j, list); }
        if (count() != 1000000) return;
      }
      print('ok');
    }
  ''');

  limited('objects of many sizes share memory', 24, '''
    class A { int a = 1; }
    class B extends A { int b = 2, c = 3, d = 4; }
    class C extends B { int e = 5, f = 6, g = 7, h = 8; A? other; }
    A? kept;
    void main() {
      var sum = 0;
      for (var i = 0; i < 3000000; i++) {
        final a = A(), b = B(), c = C();
        c.other = b; b.a = 10;
        if (i % 100000 == 0) kept = c;
        sum += a.a + c.h;
      }
      if (sum == 27000000 && kept != null) print('ok');
    }
  ''');

  limited('variables, fields and arguments keep their objects', 12, '''
    class P { int n; P? next; P(this.n, [this.next]); int get sum => n; }
    class Q extends P { Q(super.n); static Q one = Q(5); int get sum => n * 2; }
    P global = P(7);
    void garbage() { for (var i = 0; i < 200000; i++) { P(-1, P(-2)); } }
    int deep(int n, P a, P b) {
      if (n == 0) { garbage(); return a.n + b.n; }
      final c = P(n);
      final result = deep(n - 1, b, c) + a.n;
      return c.n == n ? result : -1000000;
    }
    int many(P a, P b, P c, P d, P e, P f, P g, P h, P i, P j) {
      garbage();
      return a.n + b.n + c.n + d.n + e.n + f.n + g.n + h.n + i.n + j.n;
    }
    P merge(bool first) {
      final a = P(1), b = P(2);
      P c = first ? a : b;
      for (var i = 0; i < 3; i++) { garbage(); c = P(c.n + 1, c); }
      return c;
    }
    void main() {
      final local = P(3, P(4));
      garbage();
      final other = local.next ?? global;
      if (global.n != 7 || Q.one.sum != 10 || local.n + other.n != 7) return;
      if (deep(20, P(1), P(2)) != 213) return;
      if (many(P(1), P(2), P(3), P(4), P(5), P(6), P(7), P(8), P(9), P(10)) != 55) return;
      final merged = merge(false);
      garbage();
      if (merged.n != 5 || merge(true).n != 4) return;
      P at = merged;
      for (var n = 5; n > 1; n--) { if (at.n != n) return; at = at.next ?? at; }
      print('ok');
    }
  ''');

  test('a program that creates no objects has no collector', () async {
    Future<int> size(String source) async {
      final directory = writeSources({'main.dart': source});
      final path = '${directory.path}/main.dart';
      final program = await compileProgram(path, sdk: hostSdk);
      expect(
        await compileProgram(path, sdk: hostSdk, collectsAlways: true),
        program,
      );
      return program.length;
    }

    final plain = await size("void main() => print('a');");
    expect(
      await size(
        'class A { final int n; const A(this.n); }\n'
        "int x = 0; A a = const A(1);\nvoid main() { x++; a; print('a'); }",
      ),
      lessThan(plain + 2 * 16384 + 4096),
    );
  });

  test('collecting always keeps what is used', () async {
    final source = '''
      class P { P? next; }
      void main() {
        P list = P();
        for (var i = 0; i < 2000; i++) {
          final p = P(), unused = P();
          p.next = list; unused.next = p; list = p;
        }
        var n = 1;
        P? at = list.next;
        while (at != null) { n++; at = at.next; }
        if (n == 2001) print('ok');
      }
    ''';
    expect(await _run(source, collectsAlways: true), lessThan(12 * _megabyte));
  }, skip: skipExecution);
}
