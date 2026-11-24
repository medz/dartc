import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/native.dart';

/// What a program did.
typedef Run = ({int code, String output, String errors});

/// A system that programs are run on.
///
/// Linux is in a container of Docker, where the directory for temporary files
/// is at the same place. The variables `DARTC_LINUX_ARM64` and
/// `DARTC_LINUX_X64` name such containers.
final class const Host._(final Target target, final String? _container) {
  /// Those that tests use: the ones that `DARTC_TARGETS` lists, or else this
  /// machine.
  static final List<Host> all = () {
    final listed = Platform.environment['DARTC_TARGETS'];
    if (listed == null) return [?local];
    return [
      for (final name in listed.split(',')) _of(Target.values.byName(name)),
    ];
  }();

  /// The one that tests run on, if programs can be made for it.
  static final Host? local = Platform.isMacOS
      ? const Host._(Target.macosArm64, null)
      : null;

  static Host _of(Target target) {
    if (target == .macosArm64) return const Host._(Target.macosArm64, null);
    final variable = 'DARTC_${target.label.toUpperCase()}';
    final container = Platform.environment[variable];
    return container == null
        ? throw StateError('$variable names no container.')
        : Host._(target, container);
  }

  /// Why programs cannot run anywhere, or null where they can.
  static String? get missing => all.isEmpty ? 'requires macOS' : null;

  /// What Docker gives for programs that crash, instead of negative numbers.
  static const _signals = {132, 133, 134, 135, 136, 139};

  bool get isLinux => target.system == .linux;

  /// Writes the program that [module] is, which starts with [entry], to [path].
  void write(LirModule module, String path, {required String entry}) {
    final code = emitCode(module, target: target, entry: entry);
    writeProgram(
      isLinux
          ? linkElf(code, entry: linuxEntrySymbol)
          : linkMacho(code, entry: entry, identifier: 'dartc-test'),
      path,
    );
  }

  /// Runs the C compiler in the directory [place].
  ProcessResult compileC(
    List<String> arguments,
    String place, {
    bool isCpp = false,
  }) {
    final container = _container;
    return container == null
        ? Process.runSync(
            isCpp ? 'clang++' : 'clang',
            arguments,
            workingDirectory: place,
          )
        : Process.runSync('docker', [
            'exec',
            '-w',
            place,
            container,
            isCpp ? 'g++' : 'gcc',
            ...arguments,
          ]);
  }

  /// Builds a library of [c] at [path].
  void buildLibrary(String c, String path) {
    final source = '$path.c';
    File(source).writeAsStringSync(c);
    final built = compileC([
      '-shared',
      '-fPIC',
      // Compilers differ in whether they do without rounding.
      '-ffp-contract=off',
      '-o',
      path,
      source,
    ], File(path).parent.path);
    if (built.exitCode != 0) throw StateError('${built.stderr}');
  }

  /// Runs the program at [path], for [limit] at most. The code is negative if a
  /// signal ends it.
  Future<Run> run(
    String path, {
    List<String> arguments = const [],
    String? place,
    String input = '',
    Map<String, String> environment = const {},
    Duration? limit,
  }) async {
    while (true) {
      final result = await _run(
        path,
        arguments,
        place,
        input,
        environment,
        limit,
      );
      // Files can take some time to get to a container.
      final isMissing =
          _container != null &&
          result.errors.startsWith('exec $path: no such file or directory');
      if (!isMissing) return result;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Run> _run(
    String path,
    List<String> arguments,
    String? place,
    String input,
    Map<String, String> environment,
    Duration? limit,
  ) async {
    final container = _container;
    final process = container == null
        ? await Process.start(
            path,
            arguments,
            workingDirectory: place,
            environment: environment,
          )
        : await Process.start('docker', [
            'exec',
            '-i',
            if (place != null) ...['-w', place],
            for (final MapEntry(:key, :value) in environment.entries) ...[
              '-e',
              '$key=$value',
            ],
            container,
            path,
            ...arguments,
          ]);
    final outputs = [
      for (final stream in [process.stdout, process.stderr])
        stream.transform(const Utf8Decoder(allowMalformed: true)).join(),
    ];
    process.stdin.write(input);
    // It may have ended before.
    await process.stdin.close().catchError((_) {});
    final timer = limit == null
        ? null
        : Timer(limit, () => process.kill(.sigkill));
    final [output, errors] = await Future.wait(outputs);
    timer?.cancel();
    final code = await process.exitCode;
    return (
      code: container != null && _signals.contains(code) ? 128 - code : code,
      output: output,
      errors: errors,
    );
  }
}
