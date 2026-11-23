@TestOn('mac-os')
@Tags(['native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/src/image/imports.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'support.dart';

final _unary = LirSignature([.i64], .i64);

LirModule _calling(
  Map<String, LirSignature> externals,
  LirValue? Function(LirBlock block) build,
) => LirModule(
  functions: [function('main', [], .i64, (block, _) => build(block))],
  externals: [
    for (final MapEntry(:key, :value) in externals.entries)
      LirExternal(key, value),
  ],
);

void main() {
  test('system functions are called directly and by address', () async {
    final module = _calling({'labs': _unary, 'toupper': _unary}, (block) {
      final negative = block.add(ConstInt(-30));
      final positive = block.add(Call('labs', _unary, [negative]));
      final address = block.add(SymbolAddress('toupper'));
      final letter = block.add(ConstInt(97));
      final upper = block.add(CallIndirect(address, _unary, [letter]));
      return block.add(IntBinary(.add, positive, upper));
    });
    expect(await execute(module), 30 + 65);
  }, skip: skipExecution);

  test('values survive a system call', () async {
    final module = _calling({'labs': _unary}, (block) {
      final values = [for (var i = 0; i < 30; i++) block.add(ConstInt(i))];
      LirValue sum = block.add(Call('labs', _unary, [values.first]));
      for (final value in values) {
        sum = block.add(IntBinary(.add, sum, value));
      }
      return block.add(IntBinary(.sub, sum, block.add(ConstInt(400))));
    });
    expect(await execute(module), 435 - 400);
  }, skip: skipExecution);

  test('exit ends the program', () async {
    final module = _calling(
      {
        'exit': LirSignature([.i64]),
      },
      (block) {
        final code = block.add(ConstInt(300));
        block.add(Call('exit', LirSignature([.i64]), [code]));
        return block.add(ConstInt(1));
      },
    );
    expect(await execute(module), 300 & 0xff);
  }, skip: skipExecution);

  test('several imports are bound', () async {
    final names = ['labs', 'llabs', 'toupper', 'tolower', 'isalpha', 'isdigit'];
    final module = _calling({for (final name in names) name: _unary}, (block) {
      LirValue sum = block.add(ConstInt(0));
      for (final name in names) {
        final argument = block.add(ConstInt(55));
        final result = block.add(Call(name, _unary, [argument]));
        final zero = block.add(ConstInt(0));
        final known = block.add(Compare(.ne, result, zero));
        sum = block.add(IntBinary(.add, sum, known));
      }
      return sum;
    });
    // '7' is a digit and not a letter.
    expect(await execute(module), 5);
  }, skip: skipExecution);

  test('an unknown system function stops the program', () async {
    final module = _calling({'dartc_no_such_function': _unary}, (block) {
      final zero = block.add(ConstInt(0));
      return block.add(Call('dartc_no_such_function', _unary, [zero]));
    });
    expect(await execute(module), isNegative);
  }, skip: skipExecution);

  test('the system tools read the imports', () {
    final directory = Directory.systemTemp.createTempSync('dartc-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/program';
    build(
      _calling({'labs': _unary, 'toupper': _unary}, (block) {
        return block.add(ConstInt(0));
      }),
      path,
    );
    String run(String tool, List<String> arguments) {
      final result = Process.runSync(tool, [...arguments, path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}'.replaceAll(RegExp(' +'), ' ');
    }

    final size = File(path).lengthSync();
    expect(run('/usr/bin/otool', ['-hv']), contains('EXECUTE 13 744 NOUNDEFS'));
    final commands = run('/usr/bin/otool', ['-l']);
    for (final text in [
      'segname __DATA_CONST\n vmaddr 0x0000000100004000\n'
          ' vmsize 0x0000000000004000\n fileoff 16384\n filesize 16384\n'
          ' maxprot 0x00000003\n initprot 0x00000003\n nsects 1\n flags 0x10',
      'sectname __got\n segname __DATA_CONST\n addr 0x0000000100004000\n'
          ' size 0x0000000000000010\n offset 16384\n align 2^3 (8)',
      'segname __LINKEDIT\n vmaddr 0x0000000100008000\n'
          ' vmsize 0x0000000000004000\n fileoff 32768\n'
          ' filesize ${size - 32768}',
      'cmd LC_DYLD_CHAINED_FIXUPS\n cmdsize 16\n dataoff 32768\n datasize 104',
    ]) {
      expect(commands, contains(text));
    }
    final fixups = run('/usr/bin/xcrun', ['dyld_info', '-fixups']);
    expect(fixups, matches(RegExp(r'0x100004000 bind libSystem\S*/_labs')));
    expect(fixups, matches(RegExp(r'0x100004008 bind libSystem\S*/_toupper')));
    final verified = Process.runSync('/usr/bin/codesign', [
      '--verify',
      '--strict',
      path,
    ]);
    expect(verified.exitCode, 0, reason: '${verified.stderr}');
  }, skip: skipExecution);

  test('stubs on both sides of a page boundary reach their slots', () {
    const address = 0x100003ff4, slots = 0x100007ff8;
    final names = ['a', 'b', 'c'];
    final code = ByteData.sublistView(importStubs(names, address, slots));
    for (var i = 0; i < names.length; i++) {
      final at = address + i * stubBytes;
      final adrp = code.getUint32(i * stubBytes, .little);
      final load = code.getUint32(i * stubBytes + 4, .little);
      final pages = ((adrp >> 5 & 0x7ffff) << 2 | adrp >> 29 & 3).toSigned(21);
      final offset = (load >> 10 & 0xfff) * 8;
      expect(((at >> 12) + pages << 12) + offset, slots + i * 8);
      expect(code.getUint32(i * stubBytes + 8, .little), 0xd61f0200);
    }
  });

  test('a full page of slots needs one chain', () {
    for (final (count, pages) in [(1, 1), (2, 1), (3, 2), (4, 2), (5, 3)]) {
      final table = ByteData.sublistView(
        importTable(
          [for (var i = 0; i < count; i++) 'f$i'],
          segments: 4,
          segment: 2,
          segmentOffset: 0x4000,
          pageBytes: 16,
        ),
      );
      final starts = table.getUint32(4, .little);
      final info = starts + table.getUint32(starts + 12, .little);
      expect(table.getUint16(info + 20, .little), pages, reason: '$count');
      expect(table.lengthInBytes % 8, 0);
    }
  });

  test('slots follow code that fills its pages', () {
    // The stubs end just before, at and after the end of the first page.
    for (var extra = -4; extra <= 4; extra += 4) {
      final text = Uint8List(0x4000 - 0x300 - stubBytes + extra);
      final image = ByteData.sublistView(
        linkMacho(
          EmittedCode(text, {'f': 0}, [], externals: ['labs']),
          entry: 'f',
          identifier: 'x',
        ),
      );
      const section = 32 + 72 + 72;
      final size = image.getUint64(section + 40, .little);
      final offset = image.getUint32(section + 48, .little);
      expect(size, text.length + stubBytes);
      final end = offset + size;
      // The first stub instruction and the first slot are where they belong.
      expect(image.getUint32(end - 4, .little), 0xd61f0200);
      final slots = (end + 0x3fff) & ~0x3fff;
      expect(image.getUint64(slots, .little), 1 << 63);
    }
  });

  test('chains stay within a page', () {
    final slots = ByteData.sublistView(importSlots(5, 16));
    final words = [for (var i = 0; i < 5; i++) slots.getUint64(i * 8, .little)];
    expect(words.map((word) => word & 0xffffff), [0, 1, 2, 3, 4]);
    expect(words.map((word) => word >>> 51 & 0xfff), [2, 0, 2, 0, 0]);
    expect(words.map((word) => word >>> 63), everyElement(1));
  });

  test('the table lists one chain per page', () {
    final names = [for (var i = 0; i < 5; i++) 'f$i'];
    final table = ByteData.sublistView(
      importTable(
        names,
        segments: 4,
        segment: 2,
        segmentOffset: 0x4000,
        pageBytes: 16,
      ),
    );
    final starts = table.getUint32(4, .little);
    final info = starts + table.getUint32(starts + 4 + 2 * 4, .little);
    expect(table.getUint32(starts, .little), 4);
    for (final other in [0, 1, 3]) {
      expect(table.getUint32(starts + 4 + other * 4, .little), 0);
    }
    expect(table.getUint32(info, .little), 22 + 3 * 2);
    expect(table.getUint16(info + 4, .little), 16);
    expect(table.getUint16(info + 6, .little), 6);
    expect(table.getUint64(info + 8, .little), 0x4000);
    expect(table.getUint16(info + 20, .little), 3);
    final imports = table.getUint32(8, .little);
    final symbols = table.getUint32(12, .little);
    expect(table.getUint32(16, .little), 5);
    for (final (i, name) in names.indexed) {
      final import = table.getUint32(imports + i * 4, .little);
      expect(import & 0xff, 1);
      final bytes = table.buffer.asUint8List(symbols + (import >> 9), 4);
      expect(String.fromCharCodes(bytes), '_$name\x00');
    }
  });

  test('a function here cannot also be external', () {
    expect(
      () => emitArm64(
        LirModule(
          functions: [function('f', [], null, (_, _) => null)],
          externals: [LirExternal('f', LirSignature([]))],
        ),
      ),
      throwsA(isA<LirError>()),
    );
  });

  test('programs with imports are reproducible', () {
    Uint8List link() => linkMacho(
      emitArm64(_calling({'labs': _unary}, (block) => block.add(ConstInt(0)))),
      entry: 'main',
      identifier: 'x',
    );
    expect(link(), link());
  });
}
