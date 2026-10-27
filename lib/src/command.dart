import 'allocate.dart';
import 'emit.dart';
import 'format.dart';
import 'frontend.dart';
import 'host.dart';
import 'ir.dart';
import 'library.dart';
import 'machine.dart';
import 'optimize.dart';
import 'nogc.dart';
import 'reach.dart';
import 'ssa.dart';
import 'source.dart';
import 'source_uri.dart';
import 'package_config.dart';

PackageConfig? compilerPackages(String input, String cwd, String? explicit) {
  String path;
  String uri;
  String? text;
  if (explicit != null) {
    if (explicit == '') {
      print('Missing value for --packages');
      hostExit(64);
    }
    uri = sourceInputUri(cwd, explicit);
    path = sourceUriPath('/', uri);
    text = hostReadIfExists(path);
    if (text == null) {
      print('Package configuration not found: ' + path);
      hostExit(64);
    }
  } else {
    var directory = input.substring(0, input.lastIndexOf('/') + 1);
    while (true) {
      uri = directory + '.dart_tool/package_config.json';
      path = sourceUriPath('/', uri);
      text = hostReadIfExists(path);
      if (text != null) break;
      if (directory == 'file:///') return null;
      directory = sourceResolveFileUri(directory, '../');
    }
  }
  var config = parsePackageConfig(path, text);
  resolvePackageConfig(config, uri);
  return config;
}

void runCompiler(List<String> args) {
  if (args.length == 0 || args[0] == '--help') {
    print(
      'Usage: dartc <source.dart> [-o <file>] [--target macos-arm64|linux-arm64]',
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
  targetOS = hostTarget();
  imageKind = 0;
  int argument = 1;
  while (argument < args.length) {
    String option = args[argument];
    argument = argument + 1;
    if (option.startsWith('--packages=')) {
      packages = option.substring(11);
      continue;
    }
    if (argument == args.length) {
      print('Missing value for ' + option);
      hostExit(64);
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
        targetOS = 0;
      } else if (value == 'linux-arm64') {
        targetOS = 1;
      } else {
        print('Unsupported target: ' + value);
        hostExit(64);
      }
    } else if (option == '--emit') {
      if (value == 'exe')
        imageKind = 0;
      else if (value == 'dylib')
        imageKind = 1;
      else if (value == 'object')
        imageKind = 2;
      else if (value == 'static')
        imageKind = 3;
      else {
        print('Unsupported output: ' + value);
        hostExit(64);
      }
    } else if (option == '--export') {
      selectedExport = value;
    } else {
      print('Unknown option: ' + option);
      hostExit(64);
    }
    argument = argument + 1;
  }
  if (imageKind != 0 && targetOS != 0) {
    print('Library output currently supports macOS ARM64.');
    hostExit(64);
  }
  if (imageKind != 0 && selectedExport == '') {
    print('Library output requires --export <Pointer.fromFunction binding>.');
    hostExit(64);
  }
  var cwd = hostCurrentDirectory();
  var inputUri = sourceInputUri(cwd, input);
  input = sourceUriPath('/', inputUri);
  if (output == '') {
    if (input.endsWith('.dart'))
      output = input.substring(0, input.length - 5);
    else
      output = input + '.out';
    if (imageKind == 1) output = output + '.dylib';
    if (imageKind == 2) output = output + '.o';
    if (imageKind == 3) output = output + '.a';
  }
  if (imageKind == 0 && standard == '') standard = hostStdPath();
  String runtime = '';
  if (imageKind == 0) runtime = sourceInputUri(cwd, standard);
  var config = compilerPackages(inputUri, cwd, packages);
  SourceProgram sources = collectSources(inputUri, runtime, config, targetOS);
  parseSource(sources);
  if (imageKind != 0) {
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
  var reachable = reachableFunctions(ssa);
  var checked = reachable;
  var marked = <int>[];
  var f = 0;
  while (f < functions.length) {
    var contract = functions[f].contract;
    if (contract != null && (contract.flags & contractNoGc) != 0) marked.add(f);
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
  allocateRegisters(program);
  generateCode(program);
  List<int> bytes = <int>[];
  if (imageKind == 0)
    bytes = createExecutable();
  else
    bytes = createLibrary(output);
  hostWrite(output, bytes);
  print(output + ': ' + bytes.length.toString() + ' bytes');
  if (imageKind == 0 || imageKind == 1) hostFinish(output, targetOS);
  hostExit(0);
}
