import 'dart:convert';
import 'dart:io';

import 'src/differential.dart';
import 'src/fuzz_program.dart';

const usage = '''Usage: dart tool/fuzz.dart [--compiler <native dartc>] [--std <runtime.dart>]
       [--seed <integer>] [--count <programs>] [--timeout <seconds>]
       [--case <folder containing case.json and project/>]
       dart tool/fuzz.dart --replay <saved case> [--shrink] [--attempts <count>]

Cases declare supported, unsupported, invalid, or runtimeFailure behavior.
Provide all program dependencies inside project/. Failures retain a frozen
toolchain and actual source. Replay never regenerates a program from its seed.
Use --case <saved case> with a repaired compiler to check the fix.

case.json contains {"kind":"supported","entry":"main.dart"}.
"invalid" also requires referenceError and nativeDiagnostic strings;
"unsupported" requires nativeDiagnostic. "runtimeFailure" requires
"failure":{"referenceError":"RangeError","nativeError":"list range error",
           "nativeExit":70}. Diagnostics identify each runtime's own contract.
Reduction preserves a stable labelled result/trace or compiler exception;
unlocated crashes and resource limits retain their original source for replay.
''';

Future<void> shrink(
  DifferentialSession session,
  Directory originalDirectory,
  int budget,
) async {
  final originalDescriptor = File('${originalDirectory.path}/case.json');
  final data = (jsonDecode(originalDescriptor.readAsStringSync()) as Map)
      .cast<String, Object?>();
  if (data['model'] == null)
    throw StateError('Automatic reduction requires a saved generated model.');
  var program = programFromJson((data['model'] as Map).cast<String, Object?>());
  final mainInput = 'project/${data['entry']}';
  if (File('${originalDirectory.path}/$mainInput').readAsStringSync() !=
      program.source) {
    throw StateError('Saved model does not match the actual program.');
  }
  final recorded = jsonDecode(
    File('${originalDirectory.path}/finding.json').readAsStringSync(),
  ) as Map;
  final original = await session.evaluate(originalDirectory);
  if (!original.failed || original.witness == null)
    throw StateError(
      'No stable reduction witness; retain the original for replay.',
    );
  if (original.fingerprint != recorded['fingerprint'] ||
      jsonEncode(original.inputHashes) != jsonEncode(recorded['inputHashes'])) {
    throw StateError(
      'Saved failure changed; refusing to reduce a different outcome.',
    );
  }
  final confirmation = await session.evaluate(originalDirectory);
  if (confirmation.fingerprint != original.fingerprint ||
      jsonEncode(confirmation.inputHashes) !=
          jsonEncode(original.inputHashes)) {
    throw StateError(
      'Failure or inputs are unstable; original sources retained.',
    );
  }
  // Each reduction owns a separate project. The original finding is immutable.
  final directory = session.directory.createTempSync('reduced-');
  copyFiles(
    Directory('${originalDirectory.path}/project'),
    Directory('${directory.path}/project'),
  );
  final descriptor = originalDescriptor.copySync('${directory.path}/case.json');
  File('${originalDirectory.path}/finding.json')
      .copySync('${directory.path}/original-finding.json');
  final source = File('${directory.path}/$mainInput');
  File('${directory.path}/original.dart').writeAsStringSync(program.source);
  final originalBytes = source.lengthSync();
  void checkInputs(DifferentialResult result, String expectedSource) {
    final fixed = {
      for (final entry in original.inputHashes.entries)
        if (entry.key != mainInput) entry.key: entry.value,
    };
    final actual = {
      for (final entry in result.inputHashes.entries)
        if (entry.key != mainInput) entry.key: entry.value,
    };
    if (jsonEncode(fixed) != jsonEncode(actual) ||
        source.readAsStringSync() != expectedSource) {
      throw StateError(
        'Reduction inputs changed outside the candidate source.',
      );
    }
  }

  final seen = <String>{program.source};
  var attempts = 0;
  var accepted = 0;
  try {
    while (attempts < budget) {
      var changed = false;
      for (final candidate in program.reductions()) {
        if (attempts >= budget) break;
        if (candidate.source.length >= program.source.length ||
            !seen.add(candidate.source))
          continue;
        attempts++;
        source.writeAsStringSync(candidate.source);
        final result = await session.evaluate(directory);
        checkInputs(result, candidate.source);
        if (result.fingerprint != original.fingerprint) continue;
        final again = await session.evaluate(directory);
        checkInputs(again, candidate.source);
        if (again.fingerprint != result.fingerprint ||
            jsonEncode(again.inputHashes) != jsonEncode(result.inputHashes))
          continue;
        program = candidate;
        accepted++;
        changed = true;
        break;
      }
      if (!changed) break;
    }
    source.writeAsStringSync(program.source);
    final finalCheck = await session.evaluate(directory);
    checkInputs(finalCheck, program.source);
    if (finalCheck.fingerprint != original.fingerprint)
      throw StateError('Reduced case lost the recorded failure.');
    data['model'] = program.toJson();
    writeJson(descriptor, data);
    final result = await session.evaluate(directory);
    if (result.fingerprint != original.fingerprint)
      throw StateError('Final reduced case lost the recorded failure.');
    writeJson(File('${directory.path}/finding.json'), result.toJson());
    writeJson(File('${directory.path}/reduction.json'), {
      'attempts': attempts,
      'accepted': accepted,
      'budget': budget,
      'originalCase': originalDirectory.path,
      'originalBytes': originalBytes,
      'reducedBytes': source.lengthSync(),
      'fingerprint': result.fingerprint,
    });
    stdout.writeln(
      'Reduced with $attempts attempts, $accepted accepted: ${directory.path}',
    );
  } catch (error) {
    File('${directory.path}/best-source.dart')
        .writeAsStringSync(program.source);
    stderr.writeln('Incomplete reduction retained: ${directory.path}');
    rethrow;
  }
}

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  if (arguments.contains('--help')) {
    stdout.write(usage);
    return;
  }
  final options = <String, String>{};
  var reducing = false;
  try {
    for (var i = 0; i < arguments.length; i++) {
      final option = arguments[i];
      if (option == '--shrink') {
        reducing = true;
        continue;
      }
      if (![
            '--compiler',
            '--std',
            '--seed',
            '--count',
            '--timeout',
            '--case',
            '--replay',
            '--attempts',
          ].contains(option) ||
          i + 1 == arguments.length ||
          options.containsKey(option))
        throw ArgumentError(usage);
      options[option] = arguments[++i];
    }
    int number(String name, int fallback) {
      final value = int.parse(options[name] ?? '$fallback');
      if (value < 0 || name == '--timeout' && value == 0)
        throw ArgumentError('Invalid $name');
      return value;
    }

    if (options.containsKey('--replay')) {
      if (options.keys.any((key) => key != '--replay' && key != '--attempts'))
        throw ArgumentError(usage);
      final directory = Directory(options['--replay']!).absolute;
      final session = await DifferentialSession.open(directory.parent);
      final pinnedRunner = '${session.directory.path}/runner/fuzz.dart';
      if (File.fromUri(Platform.script).absolute.path != pinnedRunner) {
        final identities = (session.metadata['identities'] as Map)
            .cast<String, String>();
        for (final entry in identities.entries.where(
          (entry) => entry.key.startsWith('runner/'),
        )) {
          final current = File('$root/tool/${entry.key.substring(7)}');
          if (!current.existsSync() ||
              await fileHash(current.path) != entry.value) {
            throw StateError(
              'Replay with the recorded runner: ${session.sdk} $pinnedRunner ${arguments.join(' ')}',
            );
          }
        }
      }
      if (reducing) {
        await shrink(session, directory, number('--attempts', 100));
      } else {
        final recorded = jsonDecode(
          File('${directory.path}/finding.json').readAsStringSync(),
        ) as Map;
        final result = await session.evaluate(directory);
        if (result.fingerprint != recorded['fingerprint'] ||
            jsonEncode(result.inputHashes) !=
                jsonEncode(recorded['inputHashes']))
          throw StateError(
            'Replay changed the recorded outcome: ${result.verdict}',
          );
        stdout.writeln('Reproduced ${result.verdict}: ${directory.path}');
      }
      return;
    }
    if (reducing || options.containsKey('--attempts'))
      throw ArgumentError('--shrink and --attempts require --replay.');
    final count = number('--count', 20);
    final seed = number('--seed', 1);
    final session = await DifferentialSession.create(
      root,
      File(options['--compiler'] ?? '$root/build/dartc-seed').absolute.path,
      File(options['--std'] ?? '$root/lib/src/runtime.dart').absolute.path,
      timeout: Duration(seconds: number('--timeout', 30)),
    );
    var passed = 0;
    var gaps = 0;
    var retain = false;
    try {
      for (var i = 0; i < (options.containsKey('--case') ? 1 : count); i++) {
        final directory = Directory('${session.directory.path}/case-$i')
          ..createSync();
        if (options.containsKey('--case')) {
          final from = Directory(options['--case']!).absolute;
          File('${from.path}/case.json')
              .copySync('${directory.path}/case.json');
          copyFiles(
            Directory('${from.path}/project'),
            Directory('${directory.path}/project'),
          );
        } else {
          final program = generateProgram(seed + i);
          Directory('${directory.path}/project').createSync();
          File('${directory.path}/project/main.dart')
              .writeAsStringSync(program.source);
          writeJson(File('${directory.path}/case.json'), {
            'kind': 'supported',
            'entry': 'main.dart',
            'seed': seed + i,
            'model': program.toJson(),
          });
        }
        final result = await session.evaluate(directory);
        if (result.failed) {
          retain = true;
          writeJson(File('${directory.path}/finding.json'), result.toJson());
          stderr.writeln(
            '${result.verdict}; retained ${directory.path}\nReplay: ${session.sdk} --packages=${session.directory.path}/packages.json ${session.directory.path}/runner/fuzz.dart --replay ${directory.path}',
          );
          exitCode = 1;
          break;
        }
        if (result.verdict == 'capability-gap') {
          retain = true;
          gaps++;
          writeJson(File('${directory.path}/finding.json'), result.toJson());
          stdout.writeln('Declared capability gap retained: ${directory.path}');
        } else {
          passed++;
          directory.deleteSync(recursive: true);
        }
      }
      writeJson(File('$root/build/fuzz/latest.json'), {
        'seed': seed,
        'passed': passed,
        'capabilityGaps': gaps,
        'retained': retain ? session.directory.path : null,
        'toolchain': session.metadata,
      });
      stdout.writeln('$passed passed, $gaps declared capability gaps.');
    } catch (_) {
      retain = true;
      stderr.writeln('Incomplete run retained: ${session.directory.path}');
      rethrow;
    } finally {
      if (!retain) session.directory.deleteSync(recursive: true);
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
