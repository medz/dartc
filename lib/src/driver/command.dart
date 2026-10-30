import '../target.dart';
import '../diagnostic.dart';
import '../emit.dart';
import '../exports.dart';
import '../format.dart';
import '../frontend.dart';
import '../header.dart';
import '../host.dart';
import '../ir.dart';
import '../library.dart';
import '../library_abi.dart';
import '../machine.dart';
import '../select.dart';
import '../optimize.dart';
import '../nogc.dart';
import '../reach.dart';
import '../ssa.dart';
import '../build_ssa.dart';
import '../source.dart';
import '../source_bundle.dart';
import '../source_uri.dart';
import '../utf8.dart';
import '../verify_ssa.dart';
import 'packages.dart';
import 'diagnostics.dart';

Never runCompiler(List<String> args, [SourceBundle? bundle]) {
  try {
    _compile(args, bundle);
  } on Diagnostic catch (error) {
    hostWriteError(formatDiagnostic(error));
    hostExit(error.exitCode);
  }
}

Never _compile(List<String> args, SourceBundle? bundle) {
  Never argumentError(String message) {
    throw Diagnostic(message, exitCode: 64);
  }

  if (args.length == 0 || args[0] == '--help') {
    print(
      'Usage: dartc <source.dart> [-o <file>] [--target macos-arm64|macos-x64|linux-arm64|linux-x64]',
    );
    print(
      '       [--emit exe|dylib|object|static] [--header <file.h>] [--std <runtime.dart>]',
    );
    print('       [--packages <package_config.json>]');
    hostExit(0);
  }
  String input = args[0];
  String output = '';
  String standard = '';
  String header = '';
  String? packages;
  compilationTarget = Target.values[hostTarget()];
  imageKind = ImageKind.executable;
  int argument = 1;
  while (argument < args.length) {
    String option = args[argument];
    argument = argument + 1;
    if (option.startsWith('--packages=')) {
      packages = option.substring(11);
      continue;
    }
    if (argument == args.length) {
      argumentError('Missing value for ' + option);
    }
    String value = args[argument];
    if (option == '-o') {
      output = value;
    } else if (option == '--std') {
      standard = value;
    } else if (option == '--packages') {
      packages = value;
    } else if (option == '--target') {
      if (value == 'macos-arm64') {
        compilationTarget = Target.macosArm64;
      } else if (value == 'macos-x64') {
        compilationTarget = Target.macosX64;
      } else if (value == 'linux-arm64') {
        compilationTarget = Target.linuxArm64;
      } else if (value == 'linux-x64') {
        compilationTarget = Target.linuxX64;
      } else {
        argumentError('Unsupported target: ' + value);
      }
    } else if (option == '--emit') {
      imageKind = switch (value) {
        'exe' => ImageKind.executable,
        'dylib' => ImageKind.dynamicLibrary,
        'object' => ImageKind.object,
        'static' => ImageKind.staticLibrary,
        _ => argumentError('Unsupported output: ' + value),
      };
    } else if (option == '--header') {
      header = value;
    } else {
      argumentError('Unknown option: ' + option);
    }
    argument = argument + 1;
  }
  if (imageKind == ImageKind.executable && header != '')
    argumentError('--header requires a library output.');
  var cwd = hostCurrentDirectory();
  var inputUri = sourceInputUri(cwd, input);
  input = sourceUriPath('/', inputUri);
  if (output == '') {
    if (input.endsWith('.dart'))
      output = input.substring(0, input.length - 5);
    else
      output = input + '.out';
    output += switch (imageKind) {
      .executable => '',
      .dynamicLibrary => targetOS == 0 ? '.dylib' : '.so',
      .object => '.o',
      .staticLibrary => '.a',
    };
  }
  final executable = imageKind == ImageKind.executable;
  if (standard != '') bundle = null;
  final runtime = bundle == null
      ? sourceInputUri(cwd, standard == '' ? hostStdPath() : standard)
      : bundle.runtime;
  var config = compilerPackages(inputUri, cwd, packages);
  SourceProgram sources = collectSources(
    inputUri,
    runtime,
    config,
    targetOS,
    bundle,
  );
  parseSource(sources);
  if (!executable) {
    if (checkedExports.isEmpty)
      argumentError('Library output requires an @Export declaration.');
    if (header == '') {
      final dot = output.lastIndexOf('.');
      header =
          (dot > output.lastIndexOf('/') ? output.substring(0, dot) : output) +
          '.h';
      if (header == output) header += '.h';
    }
    final headerUri = sourceInputUri(cwd, header);
    if (headerUri == sourceInputUri(cwd, output))
      argumentError('Header and library output paths must differ.');
    for (final file in sources.files)
      if (headerUri == sourceInputUri(cwd, file.input.path))
        argumentError(
          'Header output would overwrite a source file: ' + file.input.path,
        );
  }
  List<SsaFunction> ssa = buildSsa();
  optimizeSsa(ssa);
  verifySsa(ssa);
  var reachable = reachableFunctions(ssa);
  var checked = reachable;
  var marked = <int>[];
  var f = 0;
  while (f < functions.length) {
    var flags = functions[f].contract?.flags ?? 0;
    if ((flags & contractNoGc) != 0) marked.add(f);
    f++;
  }
  List<int> obligations = const <int>[];
  List<int> validation = const <int>[];
  if (marked.isNotEmpty) {
    validation = reachableFunctions(ssa, marked);
    obligations = checkNoGcSsa(ssa, sources, validation);
    checked = List<int>.filled(reachable.length, 0);
    f = 0;
    while (f < checked.length) {
      checked[f] = reachable[f] | validation[f];
      f++;
    }
  }
  List<MachineFunction> program = selectMachine(ssa, checked);
  if (marked.isNotEmpty) {
    checkNoGcMachine(program, obligations, sources, validation);
    f = 0;
    while (f < program.length) {
      program[f].reachable = reachable[f] != 0;
      f++;
    }
  }
  var headerBytes = <int>[];
  if (!executable) {
    checkLibraryExports(ssa, program, sources);
    headerBytes = encodeUtf8(createCHeader());
  }
  generateCode(program);
  List<int> bytes = <int>[];
  if (imageKind == ImageKind.executable)
    bytes = createExecutable();
  else
    bytes = createLibrary(output);
  hostWrite(output, bytes);
  if (!executable) hostWrite(header, headerBytes);
  print(output + ': ' + bytes.length.toString() + ' bytes');
  if (imageKind == ImageKind.executable ||
      imageKind == ImageKind.dynamicLibrary)
    hostFinish(output, targetOS);
  hostExit(0);
}
