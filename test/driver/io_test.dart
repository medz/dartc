@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/hosts.dart';
import '../support/compiler.dart';
import 'io_compression.dart';
import 'io_files.dart';
import 'io_processes.dart';
import 'io_watching.dart';
import 'io_system.dart';

const _environment = {'DARTC_TEST': 'é=1'};

/// What the official runtime does with the program at [path] and [input], in
/// the empty directory [place].
Future<Run> _official(String path, String place, String input) =>
    Host.local!.run(
      '$hostSdk/bin/dart',
      arguments: ['run', path],
      place: place,
      input: input,
      environment: _environment,
    );

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

/// What [output] says apart from the numbers of errors, which systems differ in.
String _told(String output, Host host) =>
    host.isLinux ? output.replaceAll(RegExp(r'errno = \d+'), 'errno') : output;

Future<void> _compare(
  String source,
  String input, {
  required bool collectsAlways,
}) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final place = Directory('${directory.path}/place')..createSync();
  void clear() => place
    ..deleteSync(recursive: true)
    ..createSync();
  final official = await _official(path, place.path, input);
  clear();
  expect(official.output, isNotEmpty, reason: official.errors);
  final program = '${directory.path}/program';
  for (final host in Host.all) {
    writeProgram(
      await compileProgram(
        path,
        CompileOptions(target: host.target, collectsAlways: collectsAlways),
      ),
      program,
    );
    final compiled = await host.run(
      program,
      place: place.path,
      input: input,
      environment: _environment,
    );
    clear();
    final reason =
        '${host.target}, collecting always: $collectsAlways\n'
        '${compiled.errors}';
    expect(
      _told(compiled.output, host),
      _told(official.output, host),
      reason: reason,
    );
    expect(compiled.code, official.code, reason: reason);
    // The texts of stack traces differ.
    if (official.code == 0) {
      expect(compiled.errors, official.errors, reason: reason);
    }
  }
}

void main() {
  group('dart:io', () {
    ({...filePrograms, ...systemPrograms, ...processPrograms}).forEach((
      name,
      source,
    ) {
      test(name, () => _agrees(source));
    });

    test('the environment', () => _agrees(environmentProgram));

    test('watching files', () async {
      final directory = writeSources({'main.dart': watchingProgram});
      final path = '${directory.path}/main.dart';
      final program = '${directory.path}/program';
      for (final host in Host.all) {
        writeProgram(
          await compileProgram(path, CompileOptions(target: host.target)),
          program,
        );
        final lines = (await host.run(
          program,
          place: directory.path,
        )).output.split('\n');
        if (host.isLinux) {
          // There is no official runtime there to compare with.
          var at = 0;
          for (final line in lines) {
            if (at < linuxEvents.length && line == linuxEvents[at]) at++;
          }
          expect(
            linuxEvents.skip(at),
            isEmpty,
            reason: '${host.target}\n$lines',
          );
          continue;
        }
        final official = await _official(path, directory.path, '');
        expect(lines.join('\n'), official.output, reason: '${host.target}');
      }
    });

    test('what only the system knows', () async {
      final directory = writeSources({'main.dart': platformProgram});
      final path = '${directory.path}/main.dart';
      final program = '${directory.path}/program';
      for (final host in Host.all) {
        writeProgram(
          await compileProgram(path, CompileOptions(target: host.target)),
          program,
        );
        final lines = (await host.run(program)).output.split('\n');
        final isLinux = host.isLinux;
        expect(lines[0], host.target.system.name);
        expect(lines[1], startsWith(isLinux ? 'Linux ' : 'Version '));
        expect(lines[2], '${!isLinux} $isLinux false false false false');
        expect(lines[3], isNotEmpty);
        expect(lines[4], isNotEmpty);
        expect(lines[5], '"${host.target.label}"');
        if (isLinux) continue;
        final official = await _official(path, directory.path, '');
        expect(official.output.split('\n').take(6), lines.take(6));
      }
    });

    test('compression', () {
      final data = [
        ...utf8.encode('the quick brown fox ' * 200),
        for (var i = 0; i < 3000; i++) i * i ~/ 7 & 0xff,
      ];
      return _agrees(compressionProgram, input: officialInput(data));
    });

    for (final (kind, source) in [
      ('encoder', encoderReviewProgram),
      ('decoder', decoderReviewProgram),
    ]) {
      test(
        'compression $kind filter',
        () => _compare(source, '', collectsAlways: false),
      );
    }

    test('what the official runtime decompresses', () async {
      final directory = writeSources({'main.dart': compressedProgram});
      final path = '${directory.path}/main.dart';
      final program = '${directory.path}/program';
      for (final host in Host.all) {
        writeProgram(
          await compileProgram(path, CompileOptions(target: host.target)),
          program,
        );
        final result = await host.run(program);
        expect(result.code, 0, reason: result.errors);
        final [data, ...ways] = LineSplitter.split(result.output).toList();
        expect(ways, hasLength(28));
        for (final way in ways) {
          final [name, text] = way.split(' = ');
          final back = officialDecoder(name).convert(base64.decode(text));
          expect(base64.encode(back), data, reason: '${host.target} $name');
        }
      }
    });

    inputPrograms.forEach((name, given) {
      final (source, input) = given;
      test(name, () => _agrees(source, input: input));
    });
  }, skip: Host.missing);
}
