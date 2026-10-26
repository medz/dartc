import 'dart:io';

import 'native.dart';
import 'parser.dart';

// Usage: dartc hello.dart [-o hello]
void main(List<String> args) {
  if (args.length != 1 && (args.length != 3 || args[1] != '-o') ||
      args.isNotEmpty && args.first == '--help') {
    print('Usage: dartc <source.dart> [-o <executable>]');
    exitCode = args.length == 1 && args.first == '--help' ? 0 : 64;
    return;
  }

  final input = File(args.first).absolute;
  final inputPath = input.path;
  final defaultOutput = inputPath.endsWith('.dart')
      ? inputPath.substring(0, inputPath.length - 5)
      : inputPath + '.out';
  final output = File(args.length == 3 ? args[2] : defaultOutput).absolute;
  final outputPath = output.path;

  try {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Signing requires macOS; target is macOS ARM64');
    }
    if (inputPath == outputPath ||
        output.existsSync() &&
            input.resolveSymbolicLinksSync() ==
                output.resolveSymbolicLinksSync()) {
      throw ArgumentError('Output must not overwrite the source');
    }

    final statements = parse(input.readAsStringSync());
    final program = generateNative(statements);
    output.parent.createSync(recursive: true);
    final temporary = output.parent.createTempSync('.dartc-');
    try {
      final staged = File(temporary.path + '/program');
      staged.writeAsBytesSync(program.bytes);
      for (final command in [
        ['/bin/chmod', '+x', staged.path],
        [
          '/usr/bin/codesign',
          '--force',
          '--sign',
          '-',
          '--timestamp=none',
          '--identifier',
          'dev.medz.dartc',
          staged.path,
        ],
      ]) {
        final result = Process.runSync(command.first, command.sublist(1));
        if (result.exitCode != 0) {
          throw ProcessException(
            command.first,
            command.sublist(1),
            result.stderr.toString().trim(),
            result.exitCode,
          );
        }
      }
      staged.renameSync(outputPath);
    } finally {
      temporary.deleteSync(recursive: true);
    }

    final fileSize = output.lengthSync();
    final codeSize = program.codeSize;
    final stringSize = program.stringSize;
    print('$outputPath: $fileSize bytes');
    print('ARM64 code: $codeSize bytes; UTF-8 strings: $stringSize bytes');
  } catch (error) {
    stderr.writeln('$inputPath: $error');
    exitCode = 1;
  }
}
