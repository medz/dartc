import '../target.dart';
import '../diagnostic.dart';
import '../emit.dart';
import '../format.dart';
import '../frontend.dart';
import '../host.dart';
import '../ir.dart';
import '../library.dart';
import '../machine.dart';
import '../select.dart';
import '../optimize.dart';
import '../nogc.dart';
import '../reach.dart';
import '../ssa.dart';
import '../build_ssa.dart';
import '../source.dart';
import '../source_uri.dart';
import '../verify_ssa.dart';
import 'packages.dart';

Never runCompiler(List<String> args) {
  try {
    _compile(args);
  } on Diagnostic catch (error) {
    print(error.message);
    hostExit(1);
  }
}

Never _compile(List<String> args) {
  Never argumentError(String message) {
    print(message);
    hostExit(64);
  }

  if (args.length == 0 || args[0] == '--help') {
    print(
      'Usage: dartc <source.dart> [-o <file>] [--target macos-arm64|macos-x64|linux-arm64|linux-x64]',
    );
    print(
      '       [--emit exe|dylib|object|static] [--export <FFI binding>] [--std <runtime.dart>]',
    );
    print('       [--packages <package_config.json>]');
    hostExit(0);
  }
  String input = args[0];
  String output = '';
  String standard = '';
  String selectedExport = '';
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
    } else if (option == '--export') {
      selectedExport = value;
    } else {
      argumentError('Unknown option: ' + option);
    }
    argument = argument + 1;
  }
  if (imageKind != ImageKind.executable && targetOS != 0) {
    argumentError('Library output currently supports macOS.');
  }
  if (imageKind != ImageKind.executable && selectedExport == '') {
    argumentError(
      'Library output requires --export <Pointer.fromFunction binding>.',
    );
  }
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
      .dynamicLibrary => '.dylib',
      .object => '.o',
      .staticLibrary => '.a',
    };
  }
  final executable = imageKind == ImageKind.executable;
  if (executable && standard == '') standard = hostStdPath();
  String runtime = '';
  if (executable) runtime = sourceInputUri(cwd, standard);
  var config = compilerPackages(inputUri, cwd, packages);
  SourceProgram sources = collectSources(inputUri, runtime, config, targetOS);
  parseSource(sources);
  if (imageKind != ImageKind.executable) {
    int chosen = -1;
    int i = 0;
    while (i < exportNames.length) {
      if (exportNames[i] == selectedExport) chosen = i;
      i = i + 1;
    }
    if (chosen < 0) {
      print('No FFI callback binding named ' + selectedExport);
      hostExit(64);
    }
    String name = exportNames[chosen];
    int function = exportFunctions[chosen];
    int parameters = exportParameters[chosen];
    exportNames = <String>[name];
    exportFunctions = <int>[function];
    exportParameters = <int>[parameters];
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
  generateCode(program);
  List<int> bytes = <int>[];
  if (imageKind == ImageKind.executable)
    bytes = createExecutable();
  else
    bytes = createLibrary(output);
  hostWrite(output, bytes);
  print(output + ': ' + bytes.length.toString() + ' bytes');
  if (imageKind == ImageKind.executable ||
      imageKind == ImageKind.dynamicLibrary)
    hostFinish(output, targetOS);
  hostExit(0);
}
