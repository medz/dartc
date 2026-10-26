import 'dart:io';

const program = r'''
int bias = 7;
int calls = 0;
int initial = initialize();
List<int> values = <int>[2, 3];

int initialize() {
  calls = calls + 1;
  return bias * 3;
}

int fibonacci(int n) {
  if (n < 2) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

void main(List<String> args) {
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
  print(String.fromCharCodes(<int>[0x4f60, 0x597d, 0x1f642]) == text.substring(5));
  print('value=' + (-1234567).toString());
  print(10000000000 + int.parse('0xff'));
  print(args.length);
  print(args[1]);
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
