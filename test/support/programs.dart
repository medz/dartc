import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/optimize.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../lower/support.dart';
import 'compiler.dart';
import 'expectations.dart';
import 'hosts.dart';

/// The official runtime has shown that programs end.
const _steps = 1 << 40;

/// Runs the programs in `test/programs` under [area], which do what their
/// comments tell at every level, and when collecting always.
///
/// They are files, or directories with a `main.dart` and others.
void programs(String area) {
  final entities = Directory('test/programs/$area').listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entities) {
    final name = entity.path.substring(entity.parent.path.length + 1);
    final sources = switch (entity) {
      Directory() => {
        for (final file in entity.listSync().whereType<File>())
          file.uri.pathSegments.last: file.readAsStringSync(),
      },
      _ => {'main.dart': File(entity.path).readAsStringSync()},
    };
    test(name, () => _check(sources), timeout: const Timeout.factor(6));
  }
}

Future<void> _check(Map<String, String> sources) async {
  final expected = Expectations.of(sources['main.dart']!);
  expect(expected.isTold, isTrue, reason: 'nothing is expected');
  // Outside the package, as users have them.
  final path = '${writeSources(sources).path}/main.dart';
  if (expected.isRefused) {
    final elsewhere = expected.elsewhere;
    final fails = elsewhere == null
        ? failsWith(expected.problems)
        : throwsA(
            isA<CompileFailure>().having(
              (failure) => '$failure',
              'problems',
              contains(elsewhere),
            ),
          );
    await expectLater(_translate(path), fails);
    return;
  }
  final module = await _translate(path);
  void agrees(String level, int code, String output, String errors) {
    expect(Expectations.linesOf(output), expected.output, reason: level);
    expect(Expectations.linesOf(errors), expected.errors, reason: level);
    expect(code, expected.exitCode, reason: level);
  }

  void interpret(String level, HirModule module) {
    final interpreter = HirInterpreter(module, maxSteps: _steps);
    final code = interpreter.run();
    agrees(level, _told(code), interpreter.output, interpreter.errors);
  }

  interpret('HIR', module);
  final lowered = LoweredRun(module, maxSteps: _steps);
  agrees('LIR', _told(lowered.code), lowered.output, lowered.errors);
  final optimized = optimizeProgram(module);
  interpret('optimized', optimized);
  for (final host in Host.all) {
    for (final collectsAlways in [false, if (!expected.isLong) true]) {
      final program = '$path-$collectsAlways';
      final lowered = lowerProgram(
        optimized,
        system: host.target.system,
        collectsAlways: collectsAlways,
      );
      host.write(lowered, program, entry: entrySymbol);
      final (:code, :output, :errors) = await host.run(program);
      final collecting = collectsAlways ? ', collecting always' : '';
      agrees('${host.target}$collecting', code, output, errors);
    }
  }
}

/// What the system tells of the code that a program ends with.
int _told(int? code) => (code ?? 0) & 0xff;

Future<HirModule> _translate(String path) async =>
    translateProgram(await loadProgram(path, sdk: await packagedSdk()));
