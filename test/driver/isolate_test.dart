@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(8)
library;

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/compiler.dart';
import '../support/hosts.dart';
import 'isolate_ports.dart';
import 'isolate_spawning.dart';

/// Checks that the program [source] does what it does officially, also where
/// memory is collected always.
Future<void> _agrees(String source) async {
  final directory = writeSources({'main.dart': source});
  final path = '${directory.path}/main.dart';
  final official = await Host.local!.run(
    '$hostSdk/bin/dart',
    arguments: ['run', path],
  );
  expect(official.output, isNotEmpty, reason: official.errors);
  final program = '${directory.path}/program';
  for (final host in Host.all) {
    for (final collectsAlways in [false, true]) {
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
      expect(compiled.output, official.output, reason: reason);
      expect(compiled.code, official.code, reason: reason);
      // The texts of stack traces differ.
      if (official.code == 0) {
        expect(compiled.errors, official.errors, reason: reason);
      }
    }
  }
}

void main() {
  group('dart:isolate', () {
    ({...portPrograms, ...spawningPrograms}).forEach((name, source) {
      test(name, () => _agrees(source));
    });
  }, skip: Host.missing);
}
