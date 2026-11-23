@TestOn('mac-os')
@Tags(['native'])
library;

import 'dart:io';

import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import '../lir/support.dart';
import 'support.dart';

List<int> _words(List<int> values) => [
  for (final value in values)
    for (var i = 0; i < 8; i++) value >> i * 8 & 0xff,
];

/// A program summing a chain of static objects and changing a writable one.
LirModule _module(int count, {bool withImport = false}) {
  final entry = LirBlock(), loop = LirBlock([.ref, .i64]);
  final next = LirBlock(), done = LirBlock();
  final first = entry.add(StaticObject('s0'));
  entry.end(Jump(LirEdge(loop, [first, entry.add(ConstInt(0))])));
  final [object, sum] = loop.parameters;
  final ended = loop.add(Compare(.eq, object, loop.add(ConstNull())));
  loop.end(Branch(ended, LirEdge(done), LirEdge(next)));
  final value = next.add(Load(.i64, object, offset: 8));
  final link = next.add(Load(.ref, object, offset: 16));
  final total = next.add(IntBinary(.add, sum, value));
  next.end(Jump(LirEdge(loop, [link, total])));
  final writable = done.add(StaticObject('w'));
  final linked = done.add(Load(.ref, writable, offset: 16));
  final same = done.add(
    Compare(.eq, linked, done.add(StaticObject('s${count - 1}'))),
  );
  final old = done.add(Load(.i64, writable, offset: 8));
  done
    ..add(Store(.i64, writable, done.add(IntBinary(.add, old, sum)), offset: 8))
    ..add(Store(.ref, writable, writable, offset: 16));
  final self = done.add(Load(.ref, writable, offset: 16));
  LirValue result = done.add(Load(.i64, self, offset: 8));
  if (withImport) {
    result = done.add(Call('labs', LirSignature([.i64], .i64), [result]));
  }
  done.end(Return(done.add(IntBinary(.add, result, same))));
  return LirModule(
    functions: [
      LirFunction('main', LirSignature([], .i64), [entry, loop, next, done]),
    ],
    externals: [
      if (withImport) LirExternal('labs', LirSignature([.i64], .i64)),
    ],
    statics: [
      for (var i = 0; i < count; i++)
        LirStatic(
          's$i',
          _words([7, i % 2, 0]),
          references: {if (i + 1 < count) 16: 's${i + 1}'},
        ),
      LirStatic(
        'w',
        _words([7, 10, 0]),
        references: {16: 's${count - 1}'},
        writable: true,
      ),
    ],
  );
}

void main() {
  for (final withImport in [true, false]) {
    test('objects refer to each other, imports: $withImport', () async {
      // One page, and several: 2000 objects of 32 bytes.
      for (final count in [1, 2, 40, 2000]) {
        final expected = 10 + count ~/ 2 + 1;
        expect(
          await execute(_module(count, withImport: withImport)),
          expected & 0xff,
          reason: '$count',
        );
      }
    }, skip: skipExecution);
  }

  test('the system tools read the segments', () {
    final directory = Directory.systemTemp.createTempSync('dartc-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/program';
    build(_module(2, withImport: true), path);
    String run(String tool, List<String> arguments) {
      final result = Process.runSync(tool, [...arguments, path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}'.replaceAll(RegExp(' +'), ' ');
    }

    final commands = run('/usr/bin/otool', ['-l']);
    for (final text in [
      'segname __DATA_CONST\n vmaddr 0x0000000100004000\n'
          ' vmsize 0x0000000000004000\n fileoff 16384\n filesize 16384\n'
          ' maxprot 0x00000003\n initprot 0x00000003\n nsects 2\n flags 0x10',
      'sectname __got\n segname __DATA_CONST\n addr 0x0000000100004000\n'
          ' size 0x0000000000000008\n offset 16384\n align 2^3 (8)',
      'sectname __const\n segname __DATA_CONST\n addr 0x0000000100004010\n'
          ' size 0x0000000000000038\n offset 16400\n align 2^4 (16)',
      'segname __DATA\n vmaddr 0x0000000100008000\n'
          ' vmsize 0x0000000000004000\n fileoff 32768\n filesize 16384\n'
          ' maxprot 0x00000003\n initprot 0x00000003\n nsects 1\n flags 0x0',
      'sectname __data\n segname __DATA\n addr 0x0000000100008000\n'
          ' size 0x0000000000000018\n offset 32768\n align 2^4 (16)',
      'segname __LINKEDIT\n vmaddr 0x000000010000c000',
    ]) {
      expect(commands, contains(text));
    }
    final fixups = run('/usr/bin/xcrun', ['dyld_info', '-fixups']);
    expect(fixups, matches(RegExp(r'0x100004000 bind libSystem\S*/_labs')));
    expect(fixups, contains('0x100004020 rebase 0x100004030'));
    expect(fixups, contains('0x100008010 rebase 0x100004030'));
    final verified = Process.runSync('/usr/bin/codesign', [
      '--verify',
      '--strict',
      path,
    ]);
    expect(verified.exitCode, 0, reason: '${verified.stderr}');
  }, skip: skipExecution);

  test('constant objects cannot be changed', () async {
    final block = LirBlock();
    final object = block.add(StaticObject('a'));
    // Through an address, as nothing in the language could.
    final store = Store(.i64, object, block.add(ConstInt(1)), offset: 8);
    block.add(store);
    block.end(Return(block.add(ConstInt(0))));
    final module = LirModule(
      functions: [
        LirFunction('main', LirSignature([], .i64), [block]),
      ],
      statics: [
        LirStatic('a', _words([0, 0, 0]), references: {16: 'a'}),
      ],
    );
    expect(await execute(module), isNegative);
  }, skip: skipExecution);

  test('runtime operations give what they say', () async {
    // The frame address is above the stack words, and its first word is the
    // caller's frame, which is further up.
    final outer = function('outer', [], .i64, (block, _) {
      final own = block.add(FrameAddress());
      final inner = block.add(Call('inner', LirSignature([], .i64), []));
      return block.add(Compare(.eq, own, inner));
    });
    final inner = function('inner', [], .i64, (block, _) {
      final frame = block.add(FrameAddress());
      final address = block.add(Convert(.intToPtr, frame));
      return block.add(Load(.i64, address));
    });
    final main = function('main', [], .i64, (block, _) {
      final found = block.add(Call('outer', LirSignature([], .i64), []));
      final object = block.add(StaticObject('a'));
      final bits = block.add(Convert(.ptrToInt, block.add(SymbolAddress('a'))));
      final back = block.add(Convert(.intToRef, bits));
      final same = block.add(Compare(.eq, object, back));
      return block.add(IntBinary(.add, found, same));
    });
    final module = LirModule(
      functions: [outer, inner, main],
      statics: [
        LirStatic('a', _words([0])),
      ],
    );
    expect(await execute(module), 2);
  }, skip: skipExecution);
}
