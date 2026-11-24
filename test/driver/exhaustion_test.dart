@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/compiler.dart';

const _given = '.given';

/// Like the system's `mmap`, until it has given [limit] bytes.
LirFunction _limitedMap(int limit) {
  final entry = LirBlock(List.filled(6, .i64));
  final fine = LirBlock(), full = LirBlock();
  final bytes = entry.parameters[1];
  final given = entry.add(StaticObject(_given));
  final total = entry.add(IntBinary(.add, entry.add(Load(.i64, given)), bytes));
  final fits = entry.add(Compare(.le, total, entry.add(ConstInt(limit))));
  entry.end(Branch(fits, LirEdge(fine), LirEdge(full)));
  full.end(Return(full.add(ConstInt(-1))));
  fine.add(Store(.i64, given, total));
  final words = LirSignature([.i64, .i64], .i64);
  fine.end(
    Return(fine.add(Call('calloc', words, [fine.add(ConstInt(1)), bytes]))),
  );
  return LirFunction('mmap', LirSignature(List.filled(6, .i64), .i64), [
    entry,
    fine,
    full,
  ]);
}

/// Takes memory back without freeing it, so that it can be given again.
final LirFunction _limitedUnmap = () {
  final block = LirBlock([.i64, .i64]);
  final given = block.add(StaticObject(_given));
  final old = block.add(Load(.i64, given));
  final rest = block.add(IntBinary(.sub, old, block.parameters[1]));
  block
    ..add(Store(.i64, given, rest))
    ..add(Call('free', LirSignature([.i64]), [block.parameters[0]]));
  block.end(Return(block.add(ConstInt(0))));
  return LirFunction('munmap', LirSignature([.i64, .i64], .i64), [block]);
}();

/// Runs [source] with at most [limit] bytes of memory for objects.
Future<ProcessResult> _runLimited(String source, int limit) async {
  final directory = writeSources({'main.dart': source});
  final program = translateProgram(
    await loadProgram('${directory.path}/main.dart', sdk: await packagedSdk()),
  );
  final lowered = lowerProgram(program);
  final limited = LirModule(
    functions: [...lowered.functions, _limitedMap(limit), _limitedUnmap],
    externals: [
      ...lowered.externals.where(
        (external) => external.name != 'mmap' && external.name != 'munmap',
      ),
      LirExternal('calloc', LirSignature([.i64, .i64], .i64)),
      LirExternal('free', LirSignature([.i64])),
    ],
    data: lowered.data,
    tables: lowered.tables,
    statics: [
      ...lowered.statics,
      LirStatic(_given, List.filled(8, 0), writable: true),
    ],
  );
  final path = '${directory.path}/program';
  final code = emitCode(limited);
  writeProgram(
    linkMacho(code, entry: entrySymbol, identifier: 'dartc-test'),
    path,
  );
  return Process.run(path, const []);
}

/// Runs [source] compiled after [command] in a shell.
Future<ProcessResult> _runAfter(String command, String source) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final program = '${directory.path}/program';
  writeProgram(await compileProgram(path), program);
  return Process.run('/bin/bash', ['-c', '$command; $program']);
}

void main() {
  const list = 'class P { P? next; P(this.next); }';

  test('a program that uses up its memory can go on', () async {
    final result = await _runLimited('''
      $list
      int fill() {
        P? list; var count = 0;
        try { while (true) { list = P(list); count++; } }
        on OutOfMemoryError { print('full'); }
        return count;
      }
      Object? caught() {
        P? list;
        try { while (true) { list = P(list); } } catch (e) { return e; }
      }
      void main() {
        final count = fill();
        if (count > 100000 && fill() == count) print('same');
        if (identical(caught(), caught())) print('one');
      }''', 16 << 20);
    expect(result.stdout, 'full\nfull\nsame\none\n');
    expect(result.stderr, '');
    expect(result.exitCode, 0);
  }, skip: skipExecution);

  test('nothing catches that memory is used up', () async {
    for (final limit in [0, 2000, 8 << 20]) {
      final result = await _runLimited('''
        $list
        void main() {
          print('start');
          P? list;
          while (true) { list = P(list); }
        }''', limit);
      expect(result.stdout, 'start\n');
      expect(result.stderr, 'Unhandled exception:\nOut of Memory\n');
      expect(result.exitCode, 255);
    }
  }, skip: skipExecution);

  test('errors need memory, too', () async {
    final result = await _runLimited('''
      $list
      int zero() => 0;
      void main() {
        P? list;
        try { while (true) { list = P(list); } } on OutOfMemoryError { print('a'); }
        try { 1 << (zero() - 1); print('no'); }
        on ArgumentError { print('no'); }
        on OutOfMemoryError { print('b'); }
        try { throw list ?? list!; } on P { print('c'); }
        try { 1 ~/ zero(); } on UnsupportedError { print('d'); }
        if (list != null) print('e');
      }''', 8 << 20);
    expect(result.stdout, 'a\nb\nc\nd\ne\n');
  }, skip: skipExecution);

  test('the stack overflows wherever its end is', () async {
    const source =
        '''
      $list
      int depth = 0;
      int f(int n) { depth = n; return f(n + 1) + 1; }
      void fill() { P(null); fill(); }
      class Q { Q() { Q(); } }
      void main() {
        try { f(0); } on StackOverflowError { print('a'); }
        try { fill(); } on StackOverflowError { print('b'); }
        try { Q(); } on StackOverflowError { print('c'); }
        if (depth > 1000) print('d');
        try { f(0); } finally { print('e'); }
      }''';
    for (final command in ['true', 'ulimit -s 1024', 'ulimit -s 32768']) {
      final result = await _runAfter(command, source);
      expect(result.stdout, 'a\nb\nc\nd\ne\n', reason: command);
      expect(result.stderr, 'Unhandled exception:\nStack Overflow\n');
      expect(result.exitCode, 255);
    }
  }, skip: skipExecution);

  test('output fits where the stack ends', () async {
    final result = await _runAfter('true', '''
      $list
      void f(int n) { try { f(n + 1); } on StackOverflowError { print('a'); P(null); } }
      void g(int n) { if (n % 1000 == 0) { for (var i = 0; i < 1000; i++) { P(null); } } g(n + 1); }
      void main() { f(0); try { g(1); } on Error { print('b'); } }''');
    expect(result.stdout, 'a\nb\n');
    expect(result.stderr, '');
    expect(result.exitCode, 0);
  }, skip: skipExecution);

  test('collections where the stack is deep', () async {
    final result = await _runAfter('true', '''
      $list
      int f(int n) {
        final p = P(null);
        if (n > 0) {
          final rest = f(n - 1);
          p.next = P(null);
          return p.next == null ? 0 : rest + 1;
        }
        var kept = P(null);
        for (var i = 0; i < 2000000; i++) { kept = P(null); }
        return 1;
      }
      void main() { if (f(20000) == 20001) print('ok'); }''');
    expect(result.stdout, 'ok\n');
  }, skip: skipExecution);
}
