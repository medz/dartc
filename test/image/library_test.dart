@TestOn('mac-os')
@Tags(['native'])
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/src/image/exports.dart';
import 'package:test/test.dart';

import 'support.dart';

final _work = LirSignature([.ptr, .ptr]);
final _unary = LirSignature([.i64], .i64);

/// A library whose functions use everything that object files refer to.
LirModule _module() {
  LirFunction function(
    String name,
    LirValue Function(LirBlock block, List<LirValue> words) build,
  ) {
    final block = LirBlock([.ptr, .ptr]), at = block.parameters.first;
    final words = [
      for (var i = 0; i < 2; i++)
        block.add(Load(.i64, at, offset: CallBlock.words + i * 8)),
    ];
    block
      ..add(Store(.i64, at, build(block, words), offset: CallBlock.resultWords))
      ..end(Return());
    return LirFunction(name, _work, [block]);
  }

  final double_ = LirBlock([.i64]);
  final [given] = double_.parameters;
  double_.end(Return(double_.add(IntBinary(.add, given, given))));
  return LirModule(
    functions: [
      LirFunction('double', _unary, [double_]),
      function('.add', (block, words) {
        final [a, b] = words;
        return block.add(IntBinary(.add, a, b));
      }),
      function('.use', (block, words) {
        final negative = block.add(
          IntBinary(.sub, block.add(ConstInt(0)), words[0]),
        );
        final positive = block.add(Call('labs', _unary, [negative]));
        final address = block.add(SymbolAddress('toupper'));
        final letter = block.add(CallIndirect(address, _unary, [words[1]]));
        final table = block.add(SymbolAddress('table'));
        final distance = block.add(Load(.i32, table, offset: 4));
        final twice = block.add(
          CallIndirect(block.add(PtrAdd(table, distance)), _unary, [positive]),
        );
        final bytes = block.add(
          Load(.u8, block.add(SymbolAddress('bytes')), offset: 2),
        );
        final object = block.add(StaticObject('object'));
        final other = block.add(Load(.ref, object, offset: 8));
        final value = block.add(Load(.i64, other, offset: 8));
        final counter = block.add(StaticObject('counter'));
        final count = block.add(Load(.i64, counter, offset: 8));
        final next = block.add(
          IntBinary(.add, count, block.add(ConstInt(1000000))),
        );
        block.add(Store(.i64, counter, next, offset: 8));
        LirValue sum = twice;
        for (final part in [letter, bytes, value, next]) {
          sum = block.add(IntBinary(.add, sum, part));
        }
        return sum;
      }),
    ],
    externals: [LirExternal('labs', _unary), LirExternal('toupper', _unary)],
    data: [
      LirData('bytes', [1, 2, 30]),
    ],
    tables: [
      LirTable('table', ['double', 'double']),
    ],
    statics: [
      LirStatic('object', List.filled(16, 0), references: const {8: 'other'}),
      LirStatic('other', [...List.filled(8, 0), 4, ...List.filled(7, 0)]),
      LirStatic('counter', List.filled(16, 0), writable: true),
    ],
    exports: const {'lib_add': '.add', 'lib_use': '.use'},
  );
}

const _main = '''
#include <stdio.h>
long lib_add(long a, long b);
long lib_use(long a, long b);
int main(void) {
  printf("%ld %ld %ld\\n", lib_add(40, 2), lib_use(50, 'a'), lib_use(-7, 'z'));
  return 0;
}
''';

/// 100 + 65 + 30 + 4 and a million; -7 is made positive.
const _expected = '42 1000199 2000138\n';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory(
      Directory.systemTemp
          .createTempSync('dartc-library-')
          .resolveSymbolicLinksSync(),
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/main.c').writeAsStringSync(_main);
  });

  String run(String tool, List<String> arguments) {
    final result = Process.runSync(
      tool,
      arguments,
      workingDirectory: directory.path,
    );
    expect(result.exitCode, 0, reason: '$tool $arguments: ${result.stderr}');
    expect(result.stderr, isEmpty, reason: '$tool $arguments');
    return '${result.stdout}';
  }

  void write(String name, List<int> bytes) =>
      File('${directory.path}/$name').writeAsBytesSync(bytes);

  test('object files can be linked', () {
    write('lib.o', writeMachoObject(emitArm64(_module())));
    run('clang', ['-o', 'main', 'main.c', 'lib.o']);
    expect(run('./main', []), _expected);
    final names = run('nm', ['-g', 'lib.o']);
    expect(names, contains('T _lib_add'));
    expect(names, contains('U _labs'));
  }, skip: skipExecution);

  test('archives can be linked', () {
    final code = emitArm64(_module());
    write(
      'liblib.a',
      writeArchive(writeMachoObject(code), 'lib.o', code.exports.keys),
    );
    run('clang', ['-o', 'main', 'main.c', '-L.', '-llib']);
    expect(run('./main', []), _expected);
    expect(run('ar', ['-t', 'liblib.a']), contains('lib.o'));
  }, skip: skipExecution);

  test('libraries can be linked and loaded', () {
    final path = '${directory.path}/liblib.dylib';
    final bytes = linkMachoLibrary(
      emitArm64(_module()),
      name: path,
      identifier: 'lib',
    );
    write('liblib.dylib', bytes);
    run('codesign', ['--verify', '--strict', 'liblib.dylib']);
    run('clang', ['-o', 'main', 'main.c', '-L.', '-llib']);
    expect(run('./main', []), _expected);
    final library = DynamicLibrary.open(path);
    final add = library
        .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
          'lib_add',
        );
    expect(add(1 << 40, 5), (1 << 40) + 5);
    expect(library.providesSymbol('double'), isFalse);
    expect(run('nm', ['-g', 'liblib.dylib']), contains('T _lib_use'));
  }, skip: skipExecution);

  test('tables of exports are found by any name', () {
    final random = Random(3);
    for (final count in [1, 2, 10, 400]) {
      final symbols = {
        for (var i = 0; i < count; i++)
          String.fromCharCodes([
            for (var j = 1 + random.nextInt(12); j > 0; j--)
              97 + random.nextInt(count > 10 ? 3 : 26),
          ]): random.nextInt(
            1 << 30,
          ),
      };
      final table = exportTable(symbols);
      symbols.forEach((name, address) {
        expect(_find(table, name), address, reason: name);
      });
      expect(_find(table, 'none of them'), isNull);
    }
  });
}

/// Looks [name] up in [table] as the loader does.
int? _find(List<int> table, String name) {
  var at = 0;
  int unsigned() {
    var value = 0, shift = 0;
    while (true) {
      final byte = table[at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  var rest = name;
  while (true) {
    final terminal = unsigned();
    if (rest.isEmpty) {
      if (terminal == 0) return null;
      unsigned();
      return unsigned();
    }
    at += terminal;
    int? next;
    for (var count = table[at++]; count > 0; count--) {
      final start = at;
      while (table[at] != 0) {
        at++;
      }
      final text = String.fromCharCodes(table.sublist(start, at++));
      final offset = unsigned();
      if (next == null && rest.startsWith(text)) {
        next = offset;
        rest = rest.substring(text.length);
      }
    }
    if (next == null) return null;
    at = next;
  }
}
