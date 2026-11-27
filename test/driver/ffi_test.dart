@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/hosts.dart';
import '../support/compiler.dart';
import 'ffi_addresses.dart';
import 'ffi_programs.dart';
import 'ffi_variables.dart';
import 'finalizers.dart';
import 'random_native.dart';

/// Checks that the program [source] does what it does officially.
///
/// It may create too much to collect always.
Future<void> _agrees(String source, String c, {bool isLong = false}) async {
  final directory = writeSources({});
  final library = '${directory.path}/library.so';
  final path = '${directory.path}/main.dart';
  File(path).writeAsStringSync(source.replaceAll('LIBRARY', library));
  Host.local!.buildLibrary(c, library);
  final official = await Process.run('$hostSdk/bin/dart', ['run', path]);
  expect(official.stdout, isNotEmpty, reason: '${official.stderr}');
  for (final host in Host.all) {
    if (host.isLinux) host.buildLibrary(c, library);
    for (final collectsAlways in [false, if (!isLong) true]) {
      final program = '${directory.path}/program';
      writeProgram(
        await compileProgram(
          path,
          CompileOptions(target: host.target, collectsAlways: collectsAlways),
        ),
        program,
      );
      final compiled = await host.run(program);
      final reason =
          '${host.target}, collecting always: $collectsAlways\n'
          '${compiled.errors}';
      expect(
        compiled.output
            .replaceAll(host.target.label, 'macos_arm64')
            // What stands for all libraries.
            .replaceAll('handle=0x0\n', 'handle=0xfffffffffffffffe\n'),
        official.stdout,
        reason: reason,
      );
      expect(compiled.code, official.exitCode, reason: reason);
    }
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

    test('variables', () async {
      await _agrees(variablesDart, variablesC);
    });

    test('addresses of parts of objects', () async {
      await _agrees(addressesDart, '');
    });

    test('names of types and functions', () async {
      await _agrees(namesDart, '');
    });

    test('finalizers', () async {
      await _agrees(finalizersDart, finalizersC, isLong: true);
    });

    test('finalizable locals in loops and across scope exits', () async {
      await _agrees(finalizableExitsDart, finalizersC);
    });

    test('weak references', () async {
      await _agrees(weakDart, '', isLong: true);
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
  }, skip: Host.missing);
}
