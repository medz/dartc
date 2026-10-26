import 'arm64.dart';
import 'format.dart';
import 'frontend.dart';
import 'host.dart';

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
      'Usage: dartc <source.dart> [-o <executable>] [--std <runtime.dart>]',
    );
    hostExit(0);
  }
  String input = args[0];
  String output = '';
  String standard = '';
  int argument = 1;
  while (argument < args.length) {
    if (args[argument] == '-o') {
      argument = argument + 1;
      output = args[argument];
    } else if (args[argument] == '--std') {
      argument = argument + 1;
      standard = args[argument];
    } else {
      print('Unknown option: ' + args[argument]);
      hostExit(64);
    }
    argument = argument + 1;
  }
  if (output == '') {
    if (input.endsWith('.dart')) {
      output = input.substring(0, input.length - 5);
    } else {
      output = input + '.out';
    }
  }
  if (standard == '') standard = hostStdPath();
  sourceFiles = <String>[];
  String source = hostRead(standard) + '\n' + collectSource(input);
  parseSource(source);
  generateArm64();
  List<int> bytes = createExecutable();
  hostWrite(output, bytes);
  print(output + ': ' + bytes.length.toString() + ' bytes');
  hostFinish(output);
}
