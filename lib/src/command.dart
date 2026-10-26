import 'allocate.dart';
import 'emit.dart';
import 'format.dart';
import 'frontend.dart';
import 'host.dart';
import 'ir.dart';
import 'library.dart';
import 'machine.dart';
import 'optimize.dart';
import 'ssa.dart';

List<String> sourceFiles = <String>[];

bool sourceSeen(String path) {
  int i = 0;
  while (i < sourceFiles.length) {
    if (sourceFiles[i] == path) return true;
    i = i + 1;
  }
  return false;
}

String collectSource(String path) {
  if (sourceSeen(path)) return '';
  sourceFiles.add(path);
  String source = hostRead(path);
  String folder = path.substring(0, path.lastIndexOf('/') + 1);
  String dependencies = '';
  int position = 0;
  while (position < source.length) {
    int end = source.indexOf('\n', position);
    if (end < 0) end = source.length;
    String line = source.substring(position, end);
    if (line.startsWith("import '")) {
      int close = line.indexOf("'", 8);
      String name = line.substring(8, close);
      if (!name.startsWith('dart:') && name != 'host.dart') {
        dependencies = dependencies + collectSource(folder + name);
      }
    }
    position = end + 1;
  }
  return dependencies + '\n' + source;
}

void runCompiler(List<String> args) {
  if (args.length == 0 || args[0] == '--help') {
    print(
      'Usage: dartc <source.dart> [-o <file>] [--target macos-arm64|linux-arm64]',
    );
    print(
      '       [--emit exe|dylib|object|static] [--export <FFI binding>] [--std <runtime.dart>]',
    );
    hostExit(0);
  }
  String input = args[0];
  String output = '';
  String standard = '';
  String selectedExport = '';
  targetOS = hostTarget();
  imageKind = 0;
  int argument = 1;
  while (argument < args.length) {
    String option = args[argument];
    argument = argument + 1;
    if (argument == args.length) {
      print('Missing value for ' + option);
      hostExit(64);
    }
    String value = args[argument];
    if (option == '-o') {
      output = value;
    } else if (option == '--std') {
      standard = value;
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
  if (output == '') {
    if (input.endsWith('.dart'))
      output = input.substring(0, input.length - 5);
    else
      output = input + '.out';
    if (imageKind == 1) output = output + '.dylib';
    if (imageKind == 2) output = output + '.o';
    if (imageKind == 3) output = output + '.a';
  }
  sourceFiles = <String>[];
  String source = collectSource(input);
  if (imageKind == 0) {
    if (standard == '') standard = hostStdPath();
    source = hostRead(standard) + '\n' + source;
  }
  parseSource(source);
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
  List<MachineFunction> program = selectMachine(ssa);
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
