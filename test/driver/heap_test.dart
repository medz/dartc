@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/compiler.dart';

/// Runs [source], which must print `ok`, giving the most memory that it used in
/// bytes.
Future<int> _run(String source, {bool collectsAlways = false}) async {
  final directory = writeSources({'main.dart': source});
  final program = '${directory.path}/program';
  final bytes = await compileProgram(
    '${directory.path}/main.dart',
    CompileOptions(collectsAlways: collectsAlways),
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

/// Uses what is weak, for which [count] objects are created again and again.
String weakSource(int count) =>
    '''
class P { int n; Object? other; P(this.n); }
final expando = Expando<P>();
final finalized = <int>{};
final finalizer = Finalizer<int>((n) {
  if (!finalized.add(n)) print('twice');
});
List<Object?> garbage() => [
  for (var i = 0; i < 3; i++) [for (var j = 0; j < $count; j++) P(j)],
];
List<P> kept = [];
List<WeakReference<P>> ofKept = [], ofOthers = [];
void make() {
  for (var i = 0; i < $count; i++) {
    final a = P(i), b = P(i + 1);
    expando[a] = b;
    expando[b] = a;
    a.other = b;
    finalizer.attach(a, i, detach: b);
    if (i % 5 == 0) {
      kept.add(a);
      ofKept.add(WeakReference(b));
      if (i % 10 == 0) finalizer.detach(b);
    } else {
      ofOthers.add(WeakReference(b));
    }
  }
}
void main() async {
  make();
  for (var i = 0; i < 20; i++) { garbage(); }
  await Future(() {});
  await Future(() {});
  for (final a in kept) {
    if (expando[a]!.n != a.n + 1 || expando[expando[a]!] != a) return;
  }
  for (final (i, weak) in ofKept.indexed) {
    if (weak.target!.n != kept[i].n + 1) return;
  }
  if (ofOthers.any((weak) => weak.target != null)) return;
  if (finalized.any((n) => n % 5 == 0)) return;
  if (finalized.length == $count - kept.length) print('ok');
}
''';

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

  // 16 MB, and 64 MB that are dropped.
  limited('lists of about a kilobyte share memory', 60, '''
    void main() {
      final kept = <List<Object?>>[];
      var sum = 0;
      for (var i = 0; i < 20000; i++) {
        kept.add(List.filled(100, i));
        for (var j = 0; j < 4; j++) { sum += List.filled(100, i).length; }
      }
      for (final list in kept) { sum += list[99] as int; }
      if (sum == 8000000 + 199990000) print('ok');
    }
  ''');

  // 10 MB, among which 400 MB are dropped.
  limited('memory stays small where objects are replaced', 40, '''
    class P { int a, b, c; P(this.a, this.b, this.c); }
    void main() {
      const count = 200000;
      final kept = List.filled(count, P(0, 0, 0));
      var at = 1, sum = 0;
      for (var i = 0; i < 10000000; i++) {
        at = (at * 1103515245 + 12345) & 0x7fffffff;
        kept[(at >> 8) % count] = P(i, at, 1);
      }
      for (final p in kept) { sum += p.c; }
      if (sum > 199000) print('ok');
    }
  ''');

  test('what is weak is cleared, and only that', () async {
    for (final always in [true, false]) {
      await _run(weakSource(always ? 20 : 20000), collectsAlways: always);
    }
  }, skip: skipExecution);

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
    Future<Uint8List> compile(String source, {bool always = false}) {
      final directory = writeSources({'main.dart': source});
      final path = '${directory.path}/main.dart';
      return compileProgram(path, CompileOptions(collectsAlways: always));
    }

    const source =
        'class A { final int n; const A(this.n); }\n'
        'int x = 0; A a = const A(1);\nvoid main() { x++; a; }';
    expect(await compile(source), await compile(source, always: true));
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
