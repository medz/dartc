@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/new_compiler.dart';
import 'io_files.dart';
import 'io_system.dart';

/// Runs [command] in the empty directory [place], with [input].
Future<(int, String, String)> _run(
  String command,
  List<String> arguments,
  String place,
  String input,
) async {
  final directory = Directory(place)..createSync();
  final process = await Process.start(
    command,
    arguments,
    workingDirectory: place,
    environment: {'DARTC_TEST': 'é=1'},
  );
  final outputs = [
    for (final stream in [process.stdout, process.stderr])
      stream.transform(const Utf8Decoder(allowMalformed: true)).join(),
  ];
  process.stdin.write(input);
  await process.stdin.close().catchError((_) {});
  final [output, errors] = await Future.wait(outputs);
  final code = await process.exitCode;
  directory.deleteSync(recursive: true);
  return (code, output, errors);
}

/// Checks that the program [source] does with [input] what it does officially.
///
/// It is done with less where memory is collected always.
Future<void> _agrees(String source, {String input = ''}) async {
  final lots = RegExp(r'const lots = \d+');
  final lines = input.split('\n');
  await _compare(source, input, collectsAlways: false);
  await _compare(
    source.replaceFirst(lots, 'const lots = 200'),
    lines.take(300).join('\n'),
    collectsAlways: true,
  );
}

Future<void> _compare(
  String source,
  String input, {
  required bool collectsAlways,
}) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final place = '${directory.path}/place';
  final official = await _run('$hostSdk/bin/dart', ['run', path], place, input);
  expect(official.$2, isNotEmpty, reason: official.$3);
  final program = '${directory.path}/program';
  writeProgram(
    await compileProgram(path, collectsAlways: collectsAlways),
    program,
  );
  final compiled = await _run(program, const [], place, input);
  final reason = 'collecting always: $collectsAlways\n${compiled.$3}';
  expect(compiled.$2, official.$2, reason: reason);
  expect(compiled.$1, official.$1, reason: reason);
  // The texts of stack traces differ.
  if (official.$1 == 0) expect(compiled.$3, official.$3, reason: reason);
}

void main() {
  group('dart:io', () {
    ({...filePrograms, ...systemPrograms}).forEach((name, source) {
      test(name, () => _agrees(source));
    });

    inputPrograms.forEach((name, given) {
      final (source, input) = given;
      test(name, () => _agrees(source, input: input));
    });
  }, skip: skipExecution);
}
