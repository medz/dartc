@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/new_compiler.dart';
import 'ffi_programs.dart';
import 'random_native.dart';

/// Compiles [c] to a library at [path].
void _buildLibrary(String c, String path) {
  final source = '$path.c';
  File(source).writeAsStringSync(c);
  final built = Process.runSync('clang', ['-shared', '-o', path, source]);
  if (built.exitCode != 0) throw StateError('${built.stderr}');
}

/// Checks that the program [source] does what it does officially.
///
/// It may create too much to collect always.
Future<void> _agrees(String source, String c, {bool isLong = false}) async {
  final directory = writeSources({});
  final library = '${directory.path}/library.dylib';
  _buildLibrary(c, library);
  final path = '${directory.path}/main.dart';
  File(path).writeAsStringSync(source.replaceAll('LIBRARY', library));
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  expect(official.stdout, isNotEmpty, reason: '${official.stderr}');
  for (final collectsAlways in [false, if (!isLong) true]) {
    final program = '${directory.path}/program';
    writeProgram(
      await compileProgram(path, collectsAlways: collectsAlways),
      program,
    );
    final compiled = await Process.run(program, const []);
    final reason = 'collecting always: $collectsAlways';
    expect(compiled.stdout, official.stdout, reason: reason);
    expect(compiled.exitCode, official.exitCode, reason: reason);
  }
}

void main() {
  group('dart:ffi', () {
    test('numbers, pointers and libraries', () async {
      await _agrees(numbersDart, numbersC);
    });

    test('structs, unions and arrays', () async {
      await _agrees(structsDart, structsC);
    });

    test('names of types and functions', () async {
      await _agrees(namesDart, '');
    });

    test('callbacks', () async {
      await _agrees(callbacksDart, callbacksC, isLong: true);
      final short = callbacksDart.replaceFirst('i < 3000', 'i < 3');
      await _agrees(short, callbacksC);
    });

    test('callbacks that throw', () async {
      await _agrees(throwingDart, callbacksC);
    });

    test('callbacks from other threads', () async {
      await _agrees(listeningDart, callbacksC);
    });

    for (var seed = 0; seed < 4; seed++) {
      test('random functions, seed $seed', () async {
        final (:c, :dart) = RandomNative(seed).generate('LIBRARY');
        await _agrees(dart, c);
      });
    }
  }, skip: skipExecution);
}
