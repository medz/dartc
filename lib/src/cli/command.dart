import 'dart:io';

import 'package:dartc/artifact.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

/// Runs compiler commands with caller-owned output streams.
final class CompilerCommand(final StringSink output, final StringSink errors) {
  /// Builds annotated exports, returning a process exit status.
  Future<int> run(List<String> arguments) async {
    if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
      output.writeln(_usage);
      return 0;
    }
    try {
      if (arguments.isEmpty) throw FormatException(_usage);
      final source = arguments.first;
      String? destination, header, sdkPath;
      var target = Target.host();
      var kind = OutputKind.object;
      for (var i = 1; i < arguments.length; i += 2) {
        if (i + 1 == arguments.length) {
          throw FormatException('Missing value for ${arguments[i]}');
        }
        final value = arguments[i + 1];
        switch (arguments[i]) {
          case '-o':
            destination = value;
          case '--header':
            header = value;
          case '--sdk':
            sdkPath = value;
          case '--target':
            target = Target.parse(value);
          case '--kind':
            kind = switch (value) {
              'object' => .object,
              'static' => .staticLibrary,
              'shared' => .sharedLibrary,
              _ => throw FormatException('Unknown output kind: $value'),
            };
          default:
            throw FormatException('Unknown option: ${arguments[i]}');
        }
      }
      if (destination == null) {
        throw FormatException('Missing -o output path.\n$_usage');
      }
      final compiler = Compiler(
        target,
        sdk: sdkPath == null ? null : DartSdk.at(sdkPath),
      );
      final library = await compiler.compile([source]);
      await library.write(
        File(destination),
        kind: kind,
        header: header == null ? null : File(header),
      );
      return 0;
    } on FormatException catch (error) {
      errors.writeln(error.message);
      return 64;
    } on ArgumentError catch (error) {
      errors.writeln(error.message);
      return 1;
    } on UnsupportedError catch (error) {
      errors.writeln(error.message);
      return 1;
    } on FileSystemException catch (error) {
      errors.writeln(error);
      return 1;
    }
  }
}

const _usage =
    'Usage: dartc <source.dart> -o <output> '
    '[--kind object|static|shared] [--header <file.h>] '
    '[--target macos-arm64|macos-x64|linux-arm64|linux-x64] [--sdk <root>]';
