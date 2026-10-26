import 'dart:io';

const program = r'''
class FunctionInfo {
  String name;
  int start;
  int parameters;
  int locals;
  int result;
  List<int> offsets;
  bool active;
  int flags;
  FunctionInfo(this.name, this.start, this.parameters, this.locals, this.result,
      this.offsets, this.active, this.flags);

  int frameWords(int extra) {
    this.locals += extra;
    return this.parameters + this.locals + this.flags;
  }

  String label() => this.name + ':' + this.start.toString();
  String toString() => this.label();
}

const int bias = 7;
const bool enabled = true;
const int labelValue = -1234567;
int calls = 0;
int traversals = 0;
int initial = initialize();
int spare = initialize();
List<int> values = <int>[2, 3];

int initialize() {
  calls = calls + 1;
  return bias * 3;
}

List<int> sequence() {
  traversals++;
  return <int>[1, 2, 3, 4, 5];
}

int fibonacci(int bias) {
  if (bias < 2) return bias;
  return fibonacci(bias - 1) + fibonacci(bias - 2);
}

void main(List<String> args) {
  print(calls);
  spare = 99;
  print(calls);
  print(spare);
  print(initial);
  print(calls);
  int sum = 0;
  int i = 0;
  while (i < 5) {
    sum = sum + i;
    i = i + 1;
  }
  print(sum);
  values[1] = fibonacci(8);
  values.add(5);
  print(values.length);
  print(values[1]);
  print(values.removeLast());
  values.clear();
  print(values.length);
  String text = 'Dart 你好🙂';
  print(text.substring(5));
  print(text.substring(0, 4));
  print(text.length);
  print(text.codeUnitAt(5));
  print(text.indexOf('好'));
  print(text.lastIndexOf('🙂'));
  print(text.startsWith('你好', 5));
  print(text.endsWith('🙂'));
  print(String.fromCharCodes(<int>[68, 97, 114, 116, 32, 0x4f60, 0x597d, 0x1f642]) == text);
  print('value=' + labelValue.toString());
  print(10000000000 + int.parse('0xff'));
  print(args.length);
  print(args[1]);
  var info = FunctionInfo('entry', 2, 1, 3, 1, <int>[4, 8], enabled, 13);
  var functions = <FunctionInfo>[info];
  functions[0].start = 7;
  functions[0].parameters++;
  print(functions[0].label());
  print(info.frameWords(2));
  print(functions[0].offsets[1]);
  functions[0].offsets[1] += 5;
  print(info.offsets[1]);
  print(info.active);
  print(functions.first == info);
  List<List<FunctionInfo>> groups = <List<FunctionInfo>>[functions];
  groups[0][0].start += 1;
  print(groups.first.first.label());
  int forInTotal = 0;
  for (final value in sequence()) {
    if (value == 2) continue;
    if (value == 5) break;
    forInTotal += value;
  }
  print(forInTotal);
  print(traversals);
  int doCount = 0;
  do {
    doCount++;
  } while (false);
  print(doCount);
  int branchTotal = 0;
  for (int value in <int>[1, 7, 3, 4]) {
    switch (value) {
      case 1:
      case bias:
        branchTotal += 10;
      case 3:
        continue;
      default:
        branchTotal += 1;
        break;
    }
    branchTotal += 100;
  }
  print(branchTotal);
  int labeled = 0;
  outer:
  for (var row in <int>[1, 2, 3]) {
    for (var column in <int>[1, 2, 3]) {
      if (column == 2) continue outer;
      labeled += row;
    }
  }
  finish: {
    while (true) {
      labeled += 10;
      break finish;
    }
    labeled += 100;
  }
  print(labeled);
  int multiple = 0, offset = 2;
  for (int left = 0, right = left + 6; left < right; left++, right--) {
    multiple += left + right + offset;
  }
  print(multiple);
  print('value=$multiple, enabled=$enabled, text=${text.substring(0, 4)}, info=$info');
  print('nested=${'${multiple + 1}'}');
  switch (text.substring(0, 4)) {
    case 'Dart':
      print('switch');
    default:
      print('unexpected');
  }
}
''';

ProcessResult run(
  String executable,
  List<String> arguments, {
  bool native = false,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    environment: native ? {'PATH': '/usr/bin:/bin'} : null,
    includeParentEnvironment: !native,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  String? compiler;
  var standard = '$root/lib/src/runtime.dart';
  for (var i = 0; i < args.length; i++) {
    if ((args[i] != '--compiler' && args[i] != '--std') ||
        i + 1 == args.length) {
      stderr.writeln(
        'Usage: dart test/behavior_test.dart [--compiler <path>] [--std <runtime.dart>]',
      );
      exit(64);
    }
    final option = args[i++];
    final value = File(args[i]).absolute.path;
    if (option == '--compiler') compiler = value;
    if (option == '--std') standard = value;
  }
  final temporary = Directory.systemTemp.createTempSync('dartc-behavior-');
  try {
    final source = File('${temporary.path}/program.dart')
      ..writeAsStringSync(program);
    final executable = '${temporary.path}/program';
    final sdk = Platform.resolvedExecutable;
    final arguments = ['alpha', '你好'];
    final expected = run(sdk, [source.path, ...arguments]).stdout as String;
    if (compiler == null) {
      run(sdk, [
        '$root/bin/dartc.dart',
        source.path,
        '-o',
        executable,
        '--std',
        standard,
      ]);
    } else {
      run(compiler, [
        source.path,
        '-o',
        executable,
        '--std',
        standard,
      ], native: true);
    }
    final actual = run(executable, arguments, native: true).stdout as String;
    if (actual != expected) {
      stderr.writeln('Compiled program differs from official Dart.');
      stderr.writeln('Expected:\n$expected');
      stderr.writeln('Actual:\n$actual');
      exitCode = 1;
      return;
    }
    stdout.writeln('Behavior matches official Dart.');
  } on ProcessException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
