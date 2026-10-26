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

int value = 99;
int compute(int count) => -1;
int fallback(int count) => count + 4;

class Probe {
  int value;
  Probe(this.value);
  String toString() => value.toString();
}

Probe probe = Probe(1);
String updateProbe() {
  probe.value = 2;
  return 'next';
}

class Counter {
  int value;
  List<int> values;
  Counter(this.value, this.values) {
    value += 2;
    values[0]++;
  }

  int get total => value + values[0];

  int compute(int count) {
    if (count == 0) return total;
    value++;
    return compute(count - 1);
  }

  int shadow(int value) {
    value += 3;
    return value + this.value;
  }

  int nested() {
    var result = value;
    {
      int value = 7;
      result += value;
    }
    return result + value;
  }

  int globalCall(int count) => fallback(count);
  int print(int count) => count + value;
  int builtinShadow() => print(20);
}

List<String> globalStrings = [];
List<List<bool>> globalFlags = [[]];

List<String> returned() {
  return [];
}

List<String> arrow() => [];

void take(List<String> values) {
  values.add('argument');
  print(values[0]);
}

void takeNested(List<List<String>> values) {
  values[0].add('nested argument');
  print(values[0][0]);
}

class Holder {
  List<String> values = [];
  List<List<String>> nested = [[]];
  Holder(List<String> initial) {
    this.values = initial;
  }

  void accept(List<String> values) {
    values.add('method');
    print(values[0]);
  }

  List<String> result() => [];
}

void listContexts() {
  List<String> local = [];
  local.add('local');
  print(local[0]);
  globalStrings.add('global');
  print(globalStrings[0]);
  globalFlags[0].add(true);
  print(globalFlags[0][0]);
  List<List<String>> conditional = true ? [[]] : [[]];
  conditional[0].add('conditional');
  print(conditional[0][0]);
  List<List<String>> assigned = <List<String>>[];
  assigned = [[]];
  assigned[0].add('assignment');
  print(assigned[0][0]);
  take([]);
  takeNested([[]]);
  var holder = Holder([]);
  holder.values.add('constructor');
  print(holder.values[0]);
  holder.nested[0].add('field');
  print(holder.nested[0][0]);
  holder.accept([]);
  print(holder.result().length);
  print(returned().length);
  print(arrow().length);
  var nested = <List<String>>[];
  nested.add([]);
  nested[0].add('add');
  print(nested[0][0]);
  List<List<String>> filled = List.filled(1, []);
  filled[0].add('filled context');
  print(filled[0][0]);
  var explicit = List<List<String>>.filled(1, []);
  explicit[0].add('filled explicit');
  print(explicit[0][0]);
  var inferred = List.filled(1, 'inferred');
  print(inferred[0]);
  var flags = List<bool>.filled(1, true);
  print(flags[0]);
  var objects = List<Holder>.filled(1, holder);
  print(objects[0].values[0]);
  for (List<String> values in [[]]) {
    print(values.length);
  }
  for (String value in []) {
    print(value);
  }
}

const int bias = 7;
const bool enabled = true;
const int labelValue = -1234567;
const int rtAbiVersion = -1;
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

int nativeMetadataAddress() => 77;

void main(List<String> args) {
  listContexts();
  print(nativeMetadataAddress());
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
  String copied = text.substring(5);
  print(copied + '!');
  print(copied.substring(0, 2));
  print(text.substring(0, 4));
  print(text.length);
  print(text.codeUnitAt(5));
  print(text.indexOf('好'));
  print(text.lastIndexOf('🙂'));
  print(text.startsWith('你好', 5));
  print(text.endsWith('🙂'));
  print(String.fromCharCodes(<int>[68, 97, 114, 116, 32, 0x4f60, 0x597d, 0x1f642]) == text);
  print('value=' + labelValue.toString());
  print(0.toString());
  print(9.toString());
  print((-9).toString());
  print(9223372036854775807.toString());
  print((-9223372036854775807 - 1).toString());
  print('' + text);
  print(text + '');
  print('' + '');
  print('$probe${updateProbe()}');
  probe.value = 1;
  print('${probe}${updateProbe()}');
  String foo = 'left', bar = 'right', foo$bar = 'joined';
  print('$foo$bar');
  print('${foo$bar}');
  print('$foo${bar}tail');
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
  var counter = Counter(3, <int>[8]);
  print(counter.value);
  print(counter.values[0]);
  print(counter.compute(3));
  print(counter.shadow(10));
  print(counter.nested());
  print(counter.globalCall(5));
  print(counter.builtinShadow());
  print(value);
  print(compute(4));
  int dead = 0;
  int live = 0;
  int remaining = 4;
  while (remaining > 0) {
    dead = dead * 3 + remaining;
    live += initialize();
    remaining--;
  }
  print(live);
  print(calls);
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
    final sdk = Platform.resolvedExecutable;
    final driver = compiler ?? sdk;
    List<String> compileArguments(
      File source,
      String output, [
      String? runtime,
    ]) => [
      if (compiler == null) '$root/bin/dartc.dart',
      source.path,
      '-o',
      output,
      '--std',
      runtime ?? standard,
    ];
    void compare(
      File source,
      List<String> arguments, {
      List<String> outputs = const [],
    }) {
      final executable = '${source.path}.out';
      final expected = run(sdk, [source.path, ...arguments]).stdout as String;
      final expectedFiles = [
        for (final path in outputs) File(path).readAsBytesSync(),
      ];
      run(
        driver,
        compileArguments(source, executable),
        native: compiler != null,
      );
      final actual = run(executable, arguments, native: true).stdout as String;
      if (actual != expected) {
        throw StateError(
          '${source.path} differs from official Dart.\n'
          'Expected:\n$expected\nActual:\n$actual',
        );
      }
      for (var i = 0; i < outputs.length; i++) {
        final actualBytes = File(outputs[i]).readAsBytesSync();
        final expectedBytes = expectedFiles[i];
        if (actualBytes.length != expectedBytes.length) {
          throw StateError(
            '${outputs[i]} differs in length from official Dart.',
          );
        }
        for (var byte = 0; byte < actualBytes.length; byte++) {
          if (actualBytes[byte] != expectedBytes[byte]) {
            throw StateError(
              '${outputs[i]} differs from official Dart at byte $byte.',
            );
          }
        }
      }
    }

    compare(source, ['alpha', '你好']);
    final values = File('${temporary.path}/values.dart')
      ..writeAsStringSync(
        File('$root/test/fixtures/values.dart').readAsStringSync(),
      );
    compare(values, [for (var i = 0; i < 20; i++) '参数$i🙂']);
    final failingValues = [
      "bool side() { print('rhs'); return true; } void main() { dynamic value = 1; print('before'); if (value && side()) print('after'); }",
      "void main() { dynamic value = 'wrong'; print('before'); value as int; print('after'); }",
      "void main() { dynamic value = null; print('before'); value as int; print('after'); }",
      'void main() { Object value = <Object>[1]; print(\'before\'); value as List<int>; print(\'after\'); }',
      "void main() { dynamic value = 'wrong'; print('before'); int number = value; print('after'); }",
      "void main() { List<Object> view = <int>[1]; print('before'); view[0] = 'wrong'; print('after'); }",
      "void main() { List<Object> view = <int>[1]; print('before'); view.add('wrong'); print('after'); }",
      "void main() { var values = <int>[]; print('before'); print(values[0]); }",
      "void main() { var values = <int>[1]; print('before'); print(values[-1]); }",
      "void main() { var values = <int>[1]; print('before'); values[1] = 2; print('after'); }",
      "int value() { print('rhs'); return 2; } void main() { var values = <int>[]; print('before'); values[0] = value(); print('after'); }",
      "void main() { var values = <int>[]; print('before'); values.removeLast(); print('after'); }",
      "void main() { print('before'); var values = List<int>.filled(-1, 0); print(values); }",
      "void main() { var values = List<int>.filled(0, 0); print('before'); values.add(1); print('after'); }",
      "void main() { var values = List<int>.filled(0, 0); print('before'); values.clear(); print('after'); }",
      "void main() { var values = List<int>.filled(0, 0); print('before'); values.removeLast(); print('after'); }",
      for (final change in ['owner.clear();', 'owner.add(2);'])
        '''
class Mutator {
  List<dynamic> owner;
  Mutator(this.owner);
  String toString() { $change return 'changed'; }
}
void main() {
  var values = <dynamic>[];
  values.add(Mutator(values));
  print('before');
  print(values);
  print('after');
}
''',
    ];
    for (var i = 0; i < failingValues.length; i++) {
      final source = File('${temporary.path}/value-error-$i.dart')
        ..writeAsStringSync(failingValues[i]);
      final executable = '${source.path}.out';
      final expected = Process.runSync(sdk, [source.path]);
      run(
        driver,
        compileArguments(source, executable),
        native: compiler != null,
      );
      final actual = Process.runSync(
        executable,
        [],
        environment: {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: false,
      );
      if (expected.exitCode == 0 ||
          actual.exitCode != 70 ||
          !expected.stdout.toString().startsWith('before\n') ||
          actual.stdout != expected.stdout) {
        throw StateError(
          '${source.path} did not fail at the expected value boundary.\n'
          'Official Dart: ${expected.exitCode} ${expected.stdout}${expected.stderr}\n'
          'Native: ${actual.exitCode} ${actual.stdout}${actual.stderr}',
        );
      }
    }
    final libraries = {
      'math.dart':
          'int shared() => 11; int hidden() => 90; int _private() => 8;',
      'other.dart': 'int shared() => 22;',
      'exports.dart':
          "export 'math.dart' show shared, hidden hide hidden;\n"
          "export 'other.dart' show shared hide shared;",
      'host.dart': 'int hostRead(int value) => value + 4;',
      'imports.dart': r'''
import /* directive comment */
  'exports.dart' show shared;
import './nested/../other.dart' as other show shared;
import 'math.dart' as math hide shared;
import 'host.dart';
int nativeLoad16(int value) => value + 3;
const int rtAbiVersion = -2;
void main() {
  print(shared());
  print(other.shared());
  print(math.hidden());
  print(nativeLoad16(5));
  print(hostRead(5));
}
''',
      'core.dart': "import 'dart:core' as core; void main() {core.print(42);}",
      'ordinary.dart': 'int print(int value) => value + 4;',
      'core-export.dart': "export 'dart:core' show print;",
      'priority.dart':
          "import 'dart:core'; import 'dart:core' as core; "
          "import 'ordinary.dart'; void main() { core.print(print(5)); }",
      'export-priority.dart':
          "import 'core-export.dart'; import 'dart:core' as core; "
          "import 'ordinary.dart'; void main() { core.print(print(5)); }",
      'combined-export.dart':
          "export 'dart:core' show print; export 'ordinary.dart';",
      'prefix-priority.dart':
          "import 'dart:core' as both show print; import 'ordinary.dart' as both; "
          "import 'combined-export.dart' as combined; import 'dart:core' as core; "
          'void main() { core.print(both.print(5)); core.print(combined.print(5)); }',
    };
    for (final entry in libraries.entries) {
      File('${temporary.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    compare(File('${temporary.path}/imports.dart'), []);
    compare(File('${temporary.path}/core.dart'), []);
    compare(File('${temporary.path}/priority.dart'), []);
    compare(File('${temporary.path}/export-priority.dart'), []);
    compare(File('${temporary.path}/prefix-priority.dart'), []);
    final rejected = [
      "import 'exports.dart'; void main() { print(hidden()); }",
      "import 'math.dart'; void main() { print(_private()); }",
      "import 'dart:core' hide print; void main() { print(1); }",
      "import 'math.dart' deferred as math; void main() {}",
      "import 'dart:math'; void main() {}",
      'void main() { dynamic source = 1; int slot = 0; var values = [slot = source]; List<int> typed = values; print(typed); }',
      'void value() { return 7; } void main() { value(); }',
      'void value() {} void main() { dynamic result = value(); print(result); }',
      'void main() { print(1 as int is int); }',
      'void main() { print(1 is void); }',
      'void main() { print(1 as void); }',
      'void main() { print(1 is int<String>); }',
      'void main() { print(<int>[] is List<int, String>); }',
      'void main() { int x = 3; { int x = x + 1; print(x); } }',
      'int x = 3; void main() { print(x); int x = 4; }',
      'void main() { int x = 1; int x = 2; }',
      'void f(int x, int x) {} void main() {}',
      'class C { int x; C(this.x, int x) {} } void main() {}',
      'void main() { int x = 3; for (int x = x; x < 4; x++) {} }',
      'class C { int get value => 7; void f() { print(value); int value = 9; } } void main() {}',
      'int x = 7; void main() { print(x); mark: int x = 3; }',
      'void main() { if (true) int inner = 1; print(inner); }',
    ];
    void reject(File invalid, {String? runtime, String? diagnostic}) {
      final result = Process.runSync(
        driver,
        compileArguments(invalid, '${invalid.path}.out', runtime),
        environment: compiler == null ? null : {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: compiler == null,
      );
      if (result.exitCode != 1 ||
          !'${result.stdout}${result.stderr}'.contains(
            diagnostic ?? invalid.path,
          )) {
        throw StateError(
          'Expected source diagnostic for ${invalid.path}: '
          '${result.stdout}${result.stderr}',
        );
      }
    }

    for (var i = 0; i < rejected.length; i++) {
      final invalid = File('${temporary.path}/rejected-$i.dart')
        ..writeAsStringSync(rejected[i]);
      reject(invalid);
    }
    final core = Directory('${temporary.path}/std/core')
      ..createSync(recursive: true);
    File('${File(standard).parent.path}/std/core/string_buffer.dart')
        .copySync('${core.path}/string_buffer.dart');
    final empty = File('${temporary.path}/empty.dart')
      ..writeAsStringSync('void main() {}');
    final invalidRuntimes = [
      'const int rtAbiVersion = 4; external int nativeLoad64(int pointer, int extra);',
      'const int rtAbiVersion = 4; external bool nativeTarget();',
      "const int rtAbiVersion = 4; external int nativeLoad64(int pointer); int invalid() => nativeLoad64('wrong');",
      'const int rtAbiVersion = 4; external int nativeMetadataAddress(int first, int second);',
      'const int rtAbiVersion = 4; external int nativeMetadataAddress();',
      'const int rtAbiVersion = 3;',
      'const int rtAbiVersion = 2;',
      'const int rtAbiVersion = 1;',
      'int rtAbiVersion = 4;',
      '',
    ];
    for (var i = 0; i < invalidRuntimes.length; i++) {
      final runtime = File('${temporary.path}/runtime-$i.dart')
        ..writeAsStringSync(invalidRuntimes[i]);
      reject(empty, runtime: runtime.path, diagnostic: runtime.path);
    }
    final io = File('${temporary.path}/io.dart')
      ..writeAsStringSync(
        "import '${File(standard).parent.path}/host.dart';\n" +
            r'''
void main(List<String> args) {
  var sizes = <int>[0, 1, 65535, 65536, 65537, 131073];
  var index = 0;
  while (index < sizes.length) {
    var size = sizes[index];
    var path = args[0] + index.toString();
    hostWrite(path, List<int>.filled(size, 65));
    var text = hostRead(path);
    print(text.length);
    if (text.length > 0) {
      print(text.codeUnitAt(0));
      print(text.codeUnitAt(text.length - 1));
    }
    index++;
  }
  hostWrite(args[0] + 'utf8', <int>[68, 97, 114, 116, 32, 228, 189, 160, 229, 165, 189, 240, 159, 153, 130]);
  print(hostRead(args[0] + 'utf8'));
}
''',
      );
    final outputPrefix = '${temporary.path}/io-output-';
    compare(
      io,
      [outputPrefix],
      outputs: [
        for (var i = 0; i < 6; i++) '$outputPrefix$i',
        '${outputPrefix}utf8',
      ],
    );
    stdout.writeln('Behavior matches official Dart.');
  } on ProcessException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
