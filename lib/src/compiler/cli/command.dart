import 'dart:io';

import 'package:dartc/linker.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

import '../compiler.dart';

/// Runs compiler commands with caller-owned output streams.
final class CompilerCommand(final StringSink output, final StringSink errors) {
  /// Builds a native program or library, returning a process exit status.
  Future<int> run(List<String> arguments) async {
    if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
      output.writeln(_usage);
      return 0;
    }
    try {
      if (arguments.isEmpty) throw FormatException(_usage);
      final source = arguments.first;
      String? destination, header;
      var target = Target.host();
      var kind = _OutputKind.object;
      var enableAssertions = false;
      final environment = <String, String>{};
      void define(String declaration) {
        final separator = declaration.indexOf('=');
        if (separator <= 0) {
          throw FormatException('Expected NAME=VALUE: $declaration');
        }
        environment[declaration.substring(0, separator)] = declaration
            .substring(separator + 1);
      }

      for (var i = 1; i < arguments.length; i++) {
        final option = arguments[i];
        if (option == '--enable-asserts') {
          enableAssertions = true;
          continue;
        }
        if (option.startsWith('-D') && option.length > 2) {
          define(option.substring(2));
          continue;
        }
        if (option.startsWith('--define=')) {
          define(option.substring('--define='.length));
          continue;
        }
        if (i + 1 == arguments.length) {
          throw FormatException('Missing value for $option');
        }
        final value = arguments[++i];
        switch (option) {
          case '-o':
            destination = value;
          case '--header':
            header = value;
          case '--target':
            target = Target.parse(value);
          case '--kind':
            kind = switch (value) {
              'object' => .object,
              'static' => .staticLibrary,
              'shared' => .sharedLibrary,
              'exe' => .executable,
              _ => throw FormatException('Unknown output kind: $value'),
            };
          case '-D' || '--define':
            define(value);
          default:
            throw FormatException('Unknown option: $option');
        }
      }
      if (destination == null) {
        throw FormatException('Missing -o output path.\n$_usage');
      }
      const digest = String.fromEnvironment('dartc.resources');
      final SdkSources resources;
      if (digest.isEmpty) {
        resources = await SdkSources.load();
      } else {
        final bytes = ExecutableResources(File(Platform.resolvedExecutable))
            .read();
        resources = SourceArchive(bytes, digest: digest);
      }
      final compiler = Compiler(target, resources: resources);
      final file = File(destination);
      final library = await compiler.compile(
        [source],
        environment: environment,
        enableAssertions: enableAssertions,
        output: switch (kind) {
          .object => const .object(),
          .executable => const .executable(),
          .staticLibrary => const .staticLibrary(),
          .sharedLibrary => .sharedLibrary(file.uri.pathSegments.last),
        },
      );
      await library.write(file, header: header == null ? null : File(header));
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
    } on IOException catch (error) {
      errors.writeln(error);
      return 1;
    }
  }
}

const _usage =
    'Usage: dartc <source.dart> -o <output> '
    '[--kind object|static|shared|exe] [--header <file.h>] '
    '[-DNAME=VALUE] [--define NAME=VALUE] [--enable-asserts] '
    '[--target macos-arm64|macos-x64|linux-arm64|linux-x64]';

enum _OutputKind() {
  executable,
  object,
  staticLibrary,
  sharedLibrary,
}
