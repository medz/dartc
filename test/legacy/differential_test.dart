import 'dart:convert';
import 'dart:io';

import '../../tool/src/differential.dart';
import '../../tool/src/process.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void checkStages(DifferentialResult result, Map<String, int?> codes) {
  check(
    result.stages.length == codes.length &&
        codes.keys.every(result.stages.containsKey),
    '${result.kind}: unexpected stages ${result.stages.keys}',
  );
  for (final entry in codes.entries) {
    final process = result.stages[entry.key]!;
    check(processFinished(process), '${entry.key}: incomplete process');
    check(
      process.exitCode! >= 0 &&
          (entry.value == null || process.exitCode == entry.value),
      '${entry.key}: unexpected exit ${process.exitCode}',
    );
  }
}

Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.parent.absolute.path;
  var compiler = '$root/build/dartc-seed';
  var standard = '$root/lib/src/legacy/runtime.dart';
  final options = <String>{};
  for (var i = 0; i < args.length; i++) {
    final option = args[i];
    if (!['--compiler', '--std'].contains(option) ||
        !options.add(option) ||
        i + 1 == args.length) {
      stderr.writeln(
        'Usage: dart test/legacy/differential_test.dart '
        '[--compiler <native dartc>] [--std <runtime.dart>]',
      );
      exitCode = 64;
      return;
    }
    final path = File(args[++i]).absolute.path;
    if (option == '--compiler') compiler = path;
    if (option == '--std') standard = path;
  }

  DifferentialSession? session;
  var succeeded = false;
  final captures = <String, ProcessOutcome>{};
  try {
    check(File(compiler).existsSync(), 'Native seed not found: $compiler');
    final active = await DifferentialSession.create(root, compiler, standard);
    session = active;
    Directory makeCase(
      String name,
      Map<String, Object?> contract,
      Map<String, String> files,
    ) {
      final directory = Directory('${active.directory.path}/$name')
        ..createSync();
      writeJson(File('${directory.path}/case.json'), {
        ...contract,
        'entry': 'main.dart',
      });
      for (final entry in files.entries) {
        final file = File('${directory.path}/project/${entry.key}');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
      return directory;
    }

    final supported = makeCase(
      'supported',
      {'kind': 'supported'},
      {
        'main.dart': "import 'dependency.dart';void main(){print(answer(40));}",
        'dependency.dart': 'int answer(int value)=>value+2;',
      },
    );
    final accepted = await active.evaluate(supported);
    check(accepted.verdict == 'pass' && !accepted.failed, 'Supported case');
    checkStages(accepted, {
      'inputs.collect': 0,
      for (final lane in ['reference', 'host', 'native']) ...{
        '$lane.compile': 0,
        '$lane.run': 0,
      },
    });
    for (final lane in ['reference', 'host', 'native']) {
      check(accepted.stages['$lane.run']!.stdout == '42\n', '$lane import');
    }
    check(
      accepted.inputHashes.keys.toSet().containsAll([
        'case.json',
        'project/main.dart',
        'project/dependency.dart',
      ]),
      'Saved input hashes must include local dependencies.',
    );

    final conditional = makeCase(
      'conditional',
      {'kind': 'supported'},
      {
        'main.dart': "import 'native.dart' if(dart.library.io) 'sdk.dart';void main(){print(answer());}",
        'native.dart': 'int answer()=>7;',
        'sdk.dart': 'int answer()=>7;',
      },
    );
    final selected = await active.evaluate(conditional);
    check(
      selected.verdict == 'pass',
      'Both selected dependency paths are saved',
    );
    final outside = File('${active.directory.path}/outside.dart')
      ..writeAsStringSync('int answer()=>7;');
    final external = makeCase(
      'conditional-external',
      {'kind': 'supported'},
      {
        'main.dart':
            "import '${outside.uri}' if(dart.library.io) 'sdk.dart';void main(){print(answer());}",
        'sdk.dart': 'int answer()=>7;',
      },
    );
    final unpinned = await active.evaluate(external);
    check(
      unpinned.verdict.startsWith('invalid-contract:external-dependency:') &&
          !unpinned.stages.containsKey('reference.run') &&
          !unpinned.stages.containsKey('host.run') &&
          !unpinned.stages.containsKey('native.run'),
      'A native-only external dependency must be rejected before execution',
    );

    final invalid = makeCase(
      'invalid',
      {
        'kind': 'invalid',
        'referenceError': 'must have a corresponding public name',
        'nativeDiagnostic': 'must have a public name',
      },
      {'main.dart': 'class C{int _2x;C({this._2x=1});}void main(){}'},
    );
    final rejected = await active.evaluate(invalid);
    check(rejected.verdict == 'pass' && !rejected.failed, 'Invalid case');
    checkStages(rejected, {
      'reference.compile': 254,
      'host.compile': 1,
      'native.compile': 1,
    });
    for (final lane in ['host', 'native']) {
      final process = rejected.stages['$lane.compile']!;
      check(
        process.stdout.isEmpty &&
            process.stderr.startsWith(
              '${invalid.path}/project/main.dart:1:20: ',
            ),
        '$lane rejection must identify the actual source.',
      );
    }
    check(
      rejected.stages['host.compile']!.stderr ==
          rejected.stages['native.compile']!.stderr,
      'Hosted and native source diagnostics must match.',
    );

    final unsupported = makeCase(
      'unsupported',
      {
        'kind': 'unsupported',
        'nativeDiagnostic':
            'async and generator function expressions are unsupported',
      },
      {
        'main.dart':
            'void main(){/* dartc: SSA: */var callback=()async=>7;print(7);}',
      },
    );
    final gap = await active.evaluate(unsupported);
    check(gap.verdict == 'capability-gap' && !gap.failed, 'Declared async gap');
    checkStages(gap, {
      'reference.compile': 0,
      'reference.run': 0,
      'host.compile': 1,
      'native.compile': 1,
    });
    check(
      gap.stages['reference.run']!.stdout == '7\n',
      'SDK async function declaration',
    );
    // The excerpt is source data, not the diagnostic message.
    final gapDescriptor = File('${unsupported.path}/case.json');
    final originalGap = gapDescriptor.readAsStringSync();
    try {
      final contract = (jsonDecode(originalGap) as Map).cast<String, Object?>();
      contract['nativeDiagnostic'] = 'dartc: SSA:';
      writeJson(gapDescriptor, contract);
      final mismatch = await active.evaluate(unsupported);
      check(
        mismatch.failed && mismatch.verdict == 'compile-rejected:1',
        'An arbitrary compiler exit 1 must not satisfy a source rejection.',
      );
    } finally {
      gapDescriptor.writeAsStringSync(originalGap);
    }

    final runtimeFailure = makeCase(
      'runtime-failure',
      {
        'kind': 'runtimeFailure',
        'failure': {
          'referenceError': 'RangeError',
          'nativeError': 'list range error',
          'nativeExit': 70,
        },
      },
      {
        'main.dart':
            "void main(){var values=<int>[];print('before');print(values[0]);}",
      },
    );
    final failed = await active.evaluate(runtimeFailure);
    check(failed.verdict == 'pass' && !failed.failed, 'Runtime failure case');
    checkStages(failed, {
      'inputs.collect': 0,
      'reference.compile': 0,
      'reference.run': null,
      'host.compile': 0,
      'host.run': 70,
      'native.compile': 0,
      'native.run': 70,
    });
    check(failed.stages['reference.run']!.exitCode != 0, 'SDK must fail');
    for (final lane in ['reference', 'host', 'native']) {
      check(failed.stages['$lane.run']!.stdout == 'before\n', '$lane boundary');
    }

    final child = File('${active.directory.path}/capture.dart')
      ..writeAsStringSync(r'''
import 'dart:io';
Future<void> main(List<String> args) async {
  switch(args.single) {
    case 'success': stdout.write('ok');stderr.write('err');return;
    case 'nonzero': stdout.write('before');exit(7);
    case 'timeout': await Future<void>.delayed(const Duration(seconds:30));return;
    case 'limit':
      while(true){
        stdout.write('0123456789abcdef');stderr.write('fedcba9876543210');
        await stdout.flush();await stderr.flush();
      }
    default: exit(64);
  }
}
''');
    for (final mode in ['success', 'nonzero', 'timeout', 'limit']) {
      final result = await captureProcess(
        active.sdk,
        [child.path, mode],
        timeout: mode == 'timeout'
            ? const Duration(milliseconds: 100)
            : const Duration(seconds: 30),
        outputLimit: mode == 'limit' ? 4096 : 1048576,
      );
      captures[mode] = result;
    }
    check(
      processFinished(captures['success']!) &&
          captures['success']!.exitCode == 0 &&
          captures['success']!.stdout == 'ok' &&
          captures['success']!.stderr == 'err',
      'Capture success must drain both pipes.',
    );
    check(
      processFinished(captures['nonzero']!) &&
          captures['nonzero']!.exitCode == 7 &&
          captures['nonzero']!.stdout == 'before',
      'Capture must preserve a real nonzero exit.',
    );
    final timeout = captures['timeout']!;
    check(
      timeout.timedOut &&
          !timeout.outputLimited &&
          timeout.startError == null &&
          timeout.captureError == null &&
          !processFinished(timeout) &&
          timeout.exitCode != null,
      'A timed-out child must be terminated/reaped, never a normal rejection.',
    );
    final limited = captures['limit']!;
    check(
      limited.outputLimited &&
          !limited.timedOut &&
          limited.startError == null &&
          limited.captureError == null &&
          !processFinished(limited) &&
          limited.exitCode != null &&
          limited.stdoutBytes.length + limited.stderrBytes.length == 4096,
      'Output limit must stop/reap the child and bound both pipes together.',
    );

    final finding = File('${supported.path}/finding.json');
    writeJson(finding, accepted.toJson());
    final sessionFile = File('${active.directory.path}/session.json');
    final originalSession = sessionFile.readAsStringSync();
    final recorded = (jsonDecode(originalSession) as Map)
        .cast<String, Object?>();
    (recorded['identities'] as Map)['sdkExecutable'] = '0' * 64;
    try {
      writeJson(sessionFile, recorded);
      final replay = await captureProcess(active.sdk, [
        '${active.directory.path}/runner/fuzz.dart',
        '--replay',
        supported.path,
      ]);
      captures['changed-sdk-replay'] = replay;
      check(
        processFinished(replay) &&
            replay.exitCode != 0 &&
            replay.stderr.contains('Recorded toolchain changed'),
        'Replay must refuse a changed SDK fingerprint.',
      );
    } finally {
      sessionFile.writeAsStringSync(originalSession);
    }

    final collector = File('${active.directory.path}/collect-inputs.dart');
    final originalCollector = collector.readAsStringSync();
    try {
      collector.writeAsStringSync(
        '// changed collector\n',
        mode: FileMode.append,
      );
      final replay = await captureProcess(active.sdk, [
        '${active.directory.path}/runner/fuzz.dart',
        '--replay',
        supported.path,
      ]);
      captures['changed-collector-replay'] = replay;
      check(
        processFinished(replay) &&
            replay.exitCode != 0 &&
            replay.stderr.contains('Recorded toolchain changed'),
        'Replay must refuse a changed dependency collector',
      );
    } finally {
      collector.writeAsStringSync(originalCollector);
    }

    final dependency = File('${supported.path}/project/dependency.dart');
    dependency.writeAsStringSync(
      '// changed saved input\n',
      mode: FileMode.append,
    );
    final replay = await captureProcess(active.sdk, [
      '${active.directory.path}/runner/fuzz.dart',
      '--replay',
      supported.path,
    ]);
    captures['changed-input-replay'] = replay;
    check(
      processFinished(replay) &&
          replay.exitCode != 0 &&
          replay.stderr.contains('Replay changed the recorded outcome'),
      'Replay must refuse changed saved input.',
    );
    final replayed = jsonDecode(
      File('${supported.path}/result.json').readAsStringSync(),
    ) as Map;
    check(
      replayed['verdict'] == 'pass' &&
          replayed['fingerprint'] == accepted.fingerprint &&
          (replayed['inputHashes'] as Map)['project/dependency.dart'] !=
              accepted.inputHashes['project/dependency.dart'],
      'A source-only change must be rejected even with identical behavior.',
    );
    stdout.writeln(
      'Differential buckets, process limits and replay locks pass.',
    );
    succeeded = true;
  } catch (error, stack) {
    exitCode = 1;
    if (session != null) {
      stderr.writeln('Differential test retained at ${session.directory.path}');
      writeJson(File('${session.directory.path}/harness-failure.json'), {
        'error': error.toString(),
        'stack': stack.toString(),
        'captures': {
          for (final entry in captures.entries) entry.key: entry.value.toJson(),
        },
      });
    }
    stderr.writeln(error);
  } finally {
    if (succeeded) session!.directory.deleteSync(recursive: true);
  }
}
