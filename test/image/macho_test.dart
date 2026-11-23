@TestOn('mac-os')
@Tags(['native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:test/test.dart';

import 'support.dart';

LirModule _returning(int value) {
  final block = LirBlock();
  block.end(Return(block.add(ConstInt(value))));
  return LirModule(
    functions: [
      LirFunction('main', LirSignature([], .i64), [block]),
    ],
  );
}

const _commandBytes = 0x260 - 32;

void main() {
  test('exit codes are the low eight bits', () async {
    expect(await execute(_returning(0)), 0);
    expect(await execute(_returning(42)), 42);
    expect(await execute(_returning(255)), 255);
    expect(await execute(_returning(300)), 44);
    expect(await execute(_returning(-1)), 255);
  }, skip: skipExecution);

  test('unreachable code stops the program', () async {
    final block = LirBlock()..end(Unreachable());
    final module = LirModule(
      functions: [
        LirFunction('main', LirSignature([], .i64), [block]),
      ],
    );
    expect(await execute(module), -ProcessSignal.sigtrap.signalNumber);
  }, skip: skipExecution);

  test('the system accepts the file and its signature', () {
    final directory = Directory.systemTemp.createTempSync('dartc-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/program';
    build(_returning(0), path);
    final signature = Process.runSync('/usr/bin/codesign', [
      '--verify',
      '--strict',
      path,
    ]);
    expect(signature.exitCode, 0, reason: '${signature.stderr}');
    // A changed byte of code must invalidate it.
    final bytes = File(path).readAsBytesSync();
    bytes[0x264] ^= 1;
    File(path).writeAsBytesSync(bytes);
    final broken = Process.runSync('/usr/bin/codesign', ['--verify', path]);
    expect(broken.exitCode, isNot(0));
  }, skip: skipExecution);

  test('the system tools read every header field', () {
    final directory = Directory.systemTemp.createTempSync('dartc-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/program';
    build(_returning(0), path);
    String run(String tool, List<String> arguments) {
      final result = Process.runSync(tool, [...arguments, path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}${result.stderr}'.replaceAll(RegExp(' +'), ' ');
    }

    final size = File(path).lengthSync();
    expect(
      run('/usr/bin/otool', ['-hv']),
      contains(
        'ARM64 ALL 0x00 EXECUTE 11 $_commandBytes NOUNDEFS DYLDLINK TWOLEVEL PIE',
      ),
    );
    final commands = run('/usr/bin/otool', ['-l']);
    for (final text in [
      'segname __PAGEZERO\n vmaddr 0x0000000000000000\n'
          ' vmsize 0x0000000100000000\n fileoff 0\n filesize 0\n'
          ' maxprot 0x00000000\n initprot 0x00000000\n nsects 0\n flags 0x0',
      'segname __TEXT\n vmaddr 0x0000000100000000\n'
          ' vmsize 0x0000000000004000\n fileoff 0\n filesize 16384\n'
          ' maxprot 0x00000005\n initprot 0x00000005\n nsects 1\n flags 0x0',
      'align 2^4 (16)\n reloff 0\n nreloc 0\n flags 0x80000400',
      'segname __LINKEDIT\n vmaddr 0x0000000100004000\n'
          ' vmsize 0x0000000000004000\n fileoff 16384\n'
          ' filesize ${size - 16384}\n'
          ' maxprot 0x00000001\n initprot 0x00000001\n nsects 0\n flags 0x0',
      'cmd LC_SYMTAB\n cmdsize 24',
      'cmd LC_DYSYMTAB\n cmdsize 80',
      'cmd LC_LOAD_DYLINKER\n cmdsize 32\n name /usr/lib/dyld (offset 12)',
      'cmd LC_UUID\n cmdsize 24',
      'cmd LC_BUILD_VERSION\n cmdsize 24\n platform 1\n minos 11.0\n'
          ' sdk 11.0\n ntools 0',
      'cmd LC_MAIN\n cmdsize 24\n entryoff 608\n stacksize 0',
      'cmd LC_LOAD_DYLIB\n cmdsize 56\n'
          ' name /usr/lib/libSystem.B.dylib (offset 24)\n time stamp 2',
      'current version 1.0.0\ncompatibility version 1.0.0',
      'cmd LC_CODE_SIGNATURE\n cmdsize 16\n dataoff 16384\n'
          ' datasize ${size - 16384}',
    ]) {
      expect(commands, contains(text));
    }
    final signature = run('/usr/bin/codesign', ['-dvvv']);
    expect(signature, contains('Identifier=dartc-test\n'));
    expect(signature, contains('flags=0x20002(adhoc,linker-signed)'));
    expect(signature, contains('CodeDirectory v=20400'));
  }, skip: skipExecution);

  test('the same program gives the same bytes', () {
    Uint8List link(int value) =>
        linkMacho(emitArm64(_returning(value)), entry: 'main', identifier: 'x');
    expect(link(1), link(1));
    expect(link(1), isNot(link(2)));
  });

  test('missing and unreachable symbols are errors', () {
    final error = throwsA(isA<ImageError>());
    Uint8List link(Map<String, int> functions, RelocationKind kind) =>
        linkMacho(
          EmittedCode(Uint8List(4), functions, [Relocation(0, kind, 'g')]),
          entry: 'f',
          identifier: 'x',
        );
    expect(() => link({'g': 0}, .call26), error);
    expect(() => link({'f': 0}, .call26), error);
    // The displacement field reaches 2^27 bytes back and 2^27 - 4 ahead.
    void reach(RelocationKind kind, int target, Matcher matcher) =>
        expect(() => link({'f': 0, 'g': target}, kind), matcher);
    reach(.call26, (1 << 27) - 4, returnsNormally);
    reach(.call26, 1 << 27, error);
    reach(.call26, -1 << 27, returnsNormally);
    reach(.call26, (-1 << 27) - 4, error);
    reach(.page21, (1 << 32) - 0x1000, returnsNormally);
    reach(.page21, 1 << 32, error);
    reach(.page21, -1 << 32, returnsNormally);
    reach(.page21, (-1 << 32) - 0x1000, error);
  });

  test('the signature marks a main program', () {
    final file = ByteData.sublistView(
      linkMacho(emitArm64(_returning(0)), entry: 'main', identifier: 'x'),
    );
    // Offsets come from the system's code directory structure.
    final at = 16384 + 20;
    expect(file.getUint32(at), 0xfade0c02);
    expect(file.getUint8(at + 38), 0); // Platform.
    expect(file.getUint64(at + 64), 0); // Executable segment start.
    expect(file.getUint64(at + 72), 16384); // Executable segment size.
    expect(file.getUint64(at + 80), 1); // A main program.
  });

  test('relocations fill the encoded fields', () {
    final code = EmittedCode(
      Uint8List(0x6000),
      {'f': 0, 'ahead': 0x5004},
      [
        Relocation(0, .call26, 'ahead'),
        Relocation(0x5008, .call26, 'f'),
        Relocation(4, .page21, 'ahead'),
        Relocation(8, .pageOffset12, 'ahead'),
        Relocation(0x500c, .page21, 'f'),
      ],
    );
    final image = ByteData.sublistView(
      linkMacho(code, entry: 'f', identifier: 'x'),
    );
    // The section header names the code's address and file offset.
    final address = image.getUint64(32 + 72 + 72 + 32, .little);
    final offset = image.getUint32(32 + 72 + 72 + 48, .little);
    int word(int at) => image.getUint32(offset + at, .little);
    int page(int at) => (address + at) >> 12;
    int pages(int word) =>
        ((word >> 5 & 0x7ffff) << 2 | word >> 29 & 3).toSigned(21);
    expect(word(0), 0x5004 >> 2);
    expect(word(0x5008), (-0x5008 >> 2) & 0x3ffffff);
    expect(pages(word(4)), page(0x5004) - page(4));
    expect(word(8) >> 10, (address + 0x5004) & 0xfff);
    expect(pages(word(0x500c)), page(0) - page(0x500c));
    expect(pages(word(0x500c)), isNegative);
  });
}
