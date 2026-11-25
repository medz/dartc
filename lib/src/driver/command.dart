import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'compile.dart';
import 'files.dart';
import 'sdk.dart';

const _usage = '''
Usage: dartc <source.dart> -o <output> [options]

  --kind <kind>        exe, which is the default, object, static or shared
  --target <target>    macos-arm64, linux-arm64 or linux-x64
  --header <file.h>    where to write declarations for C
  -D<name>=<value>     what fromEnvironment knows; also --define <name>=<value>
  --enable-asserts     check assertions
  -h, --help           show this''';

/// A command that cannot be understood.
final class _UsageError(final String message) implements Exception;

/// Compiles as [arguments] tell, with the SDK that [sdk] gives. Gives the exit
/// code.
Future<int> runCommand(
  List<String> arguments, {
  required StringSink output,
  required StringSink errors,
  required Future<SdkFiles> Function() sdk,
}) async {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    output.writeln(_usage);
    return 0;
  }
  try {
    await _Command(arguments, sdk).run();
    return 0;
  } on _UsageError catch (error) {
    errors.writeln(error.message);
    return 64;
  } on CompileFailure catch (failure) {
    errors.writeln(failure);
    return 1;
  } on IOException catch (error) {
    errors.writeln(error);
    return 1;
  }
}

final class _Command(
  List<String> arguments,
  final Future<SdkFiles> Function() _sdk,
) {
  late final String _source, _output;
  String? _header;
  LibraryKind? _kind;
  Target? _target = hostTarget;
  bool _checksAssertions = false;
  final _environment = <String, String>{};

  this {
    final sources = <String>[];
    String? output;
    final rest = arguments.iterator;
    while (rest.moveNext()) {
      final argument = rest.current;
      // What follows the name of an option, in the same argument or the next.
      String value(String name) {
        if (argument.startsWith('$name=')) {
          return argument.substring(name.length + 1);
        }
        if (rest.moveNext()) return rest.current;
        throw _UsageError('Missing value for $name.');
      }

      switch (argument.split('=').first) {
        case '-o':
          output = value('-o');
        case '--header':
          _header = value('--header');
        case '--kind':
          _kind = _kindOf(value('--kind'));
        case '--target':
          _target = _targetOf(value('--target'));
        case '--define':
          _define(value('--define'));
        case '-D':
          _define(value('-D'));
        case '--enable-asserts':
          _checksAssertions = true;
        case final name when name.startsWith('-D'):
          _define(argument.substring(2));
        case final name when name.startsWith('-'):
          throw _UsageError('Unknown option: $argument\n$_usage');
        default:
          sources.add(argument);
      }
    }
    if (sources.length != 1 || output == null) throw _UsageError(_usage);
    if (_header != null && _kind == null) {
      throw _UsageError('Only libraries have headers.');
    }
    _source = sources.single;
    _output = output;
  }

  static LibraryKind? _kindOf(String name) {
    if (name == 'exe') return null;
    return LibraryKind.values.where((kind) => kind.name == name).firstOrNull ??
        (throw _UsageError('Unknown kind of output: $name'));
  }

  static Target _targetOf(String name) =>
      Target.values
          .where((target) => target.label == name.replaceAll('-', '_'))
          .firstOrNull ??
      (throw _UsageError('Unknown target: $name'));

  void _define(String declaration) {
    final at = declaration.indexOf('=');
    if (at <= 0) throw _UsageError('Expected name=value: $declaration');
    final name = declaration.substring(0, at);
    if (name.startsWith('dart.')) {
      throw _UsageError('Only the compiler tells what $name is.');
    }
    _environment[name] = declaration.substring(at + 1);
  }

  Future<void> run() async {
    final target =
        _target ??
        (throw _UsageError('Tell a --target; this machine is none.'));
    final options = CompileOptions(
      target: target,
      environment: _environment,
      checksAssertions: _checksAssertions,
    );
    final sdk = sdkFor(target, await _sdk(), environment: _environment);
    final Uint8List bytes;
    final kind = _kind, header = _header;
    if (kind == null) {
      bytes = await buildProgram(_source, sdk, options);
    } else {
      final library = await buildLibrary(
        _source,
        kind,
        sdk,
        name: _output,
        options: options,
      );
      bytes = library.bytes;
      if (header != null) File(header).writeAsStringSync(library.header);
    }
    final isExecutable = kind == null || kind == .shared;
    writeOutput(bytes, _output, isExecutable: isExecutable);
  }
}
