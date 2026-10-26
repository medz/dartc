import 'dart:io';

import '../lib/src/layout.dart';

const program = r'''
Never neverStops() { while (true) {} }
Never get neverGetter => neverStops();
void neverGetterCall() { neverGetter(); }
Never nullAssertion(Null value) {
  value!;
  var inferred = [value];
  List<Never> checked = inferred;
  print(checked);
  return value;
}
int neverAssertion(Never value) { value!; }
void voidCastNever() {
  void value = 1;
  value as Never;
  var values = [value];
  List<Never> checked = values;
  print(checked);
}
int neverLocalCoalescing(Never value, dynamic fallback) {
  value ??= fallback;
}

Never neverExpressions(Never value) {
  value!<int>();
  (value as Never)<int>();
  Never property = value.missing;
  Never indexed = value['index'];
  var assignments = [value.missing = 1];
  List<int> typed = assignments;
  var compounds = [value[true] += 1];
  List<Never> checked = compounds;
  var ifNull = [value.missing ??= 1];
  List<int> selected = ifNull;
  value<int, String>(typed, other: property);
  value.foo(checked, selected, other: indexed);
  return value.toString(1, other: true);
}

Never neverNegation(Never value) => -value;
Never neverRelation(Never value) => value < 1;
num neverRightArithmetic(Never value) => 1 + value;
bool neverLogical(Never value) => !value || value;

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
  var iterationValues = <int>[1, 2, 3];
  var iterationTotal = 0;
  for (final value in iterationValues) {
    iterationTotal += value;
    iterationValues[1] = 4;
    iterationValues.add(9);
    iterationValues.removeLast();
  }
  print(iterationTotal);
  for (final value in iterationValues) {
    iterationValues.clear();
    print(value);
    break;
  }
  print(iterationValues.length);
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
    final roots = File('${temporary.path}/roots.dart')
      ..writeAsStringSync(
        File('$root/test/fixtures/roots.dart')
            .readAsStringSync()
            .replaceAll("'../../lib/src/runtime.dart'", "'$standard'")
            .replaceAll(
              "'../../lib/src/layout.dart'",
              "'${File(standard).parent.path}/layout.dart'",
            ),
      );
    final rootsExecutable = '${roots.path}.out';
    run(
      driver,
      compileArguments(roots, rootsExecutable),
      native: compiler != null,
    );
    final rootOutput = run(rootsExecutable, [
      'alpha',
      '你好🙂',
    ], native: true).stdout;
    if (rootOutput != 'roots ok\n') {
      throw StateError(
        'Unexpected native root enumeration output: $rootOutput',
      );
    }
    final exhaustedRoots = Process.runSync(
      rootsExecutable,
      ['capacity'],
      environment: {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    if (exhaustedRoots.exitCode != 70 || exhaustedRoots.stdout != 'before\n') {
      throw StateError(
        'Root worklist exhaustion did not fail at the expected boundary: '
        '${exhaustedRoots.stdout}${exhaustedRoots.stderr}',
      );
    }
    final namedEntry = File('${temporary.path}/named-entry.dart')
      ..writeAsStringSync(
        "void main({String label = 'named', bool flag = true, List<List<int>> values = const [[]]}) { "
        'print(label); print(flag); print(values); }',
      );
    compare(namedEntry, ['ignored', '你好']);
    final twoEntry = File('${temporary.path}/two-entry.dart')
      ..writeAsStringSync(
        "void main(List<String> args, [Object? message = 'default', int third = 3]) { "
        'print(args); print(message); print(third); }',
      );
    compare(twoEntry, ['alpha', '你好🙂']);
    final invalidEntry = File('${temporary.path}/invalid-entry.dart')
      ..writeAsStringSync(
        "void main(List<String> args, [int second = 1]) { print('body'); }",
      );
    final expectedEntry = Process.runSync(sdk, [invalidEntry.path]);
    final entryExecutable = '${invalidEntry.path}.out';
    run(
      driver,
      compileArguments(invalidEntry, entryExecutable),
      native: compiler != null,
    );
    final actualEntry = Process.runSync(
      entryExecutable,
      [],
      environment: {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    if (expectedEntry.exitCode == 0 ||
        actualEntry.exitCode != 70 ||
        expectedEntry.stdout != '' ||
        actualEntry.stdout != expectedEntry.stdout) {
      throw StateError('Entry argument checks must fail before the main body.');
    }
    final failingValues = [
      "void main() { print('before'); print('abc'.codeUnitAt(-1)); }",
      "void main() { print('before'); print('abc'.codeUnitAt(3)); }",
      "void main() { print('before'); print('abc'[9223372036854775807]); }",
      "void main() { print('before'); print('abc'.substring(-1)); }",
      "void main() { print('before'); 'abc'.substring(0, -1); print('after'); }",
      "void main() { print('before'); print('abc'.substring(2, 1)); }",
      "void main() { print('before'); print('abc'.substring(0, 4)); }",
      "void main() { print('before'); print('abc'.indexOf('', 4)); }",
      "void main() { print('before'); print('abc'.lastIndexOf('', -1)); }",
      "void main() { print('before'); print('abc'.startsWith('', 4)); }",
      "void main() { print('before'); print(String.fromCharCodes(<int>[-1])); }",
      "void main() { print('before'); print(String.fromCharCodes(<int>[1114112])); }",
      "bool side() { print('rhs'); return true; } void main() { dynamic value = 1; print('before'); if (value && side()) print('after'); }",
      "void main() { dynamic value = 'wrong'; print('before'); value as int; print('after'); }",
      "void main() { dynamic value = null; print('before'); value as int; print('after'); }",
      "void main() { dynamic value = null; print('before'); value as Never; print('after'); }",
      'void main() { dynamic value = null; print("before"); value!; print("after"); }',
      'String? missing() { print("getter"); return null; } void main() { print("before"); missing()!; print("after"); }',
      'void main() { Null value; print("before"); value!; print("after"); }',
      "void main() { List<String> values = <Never>[]; print('before'); values.add('x'); }",
      "void main() { dynamic value = 1; print('before'); value as bool; print('after'); }",
      'void wrong() => false; void main() { print("before"); wrong() as int; print("after"); }',
      'void missing() {} void main() { print("before"); missing() as String; print("after"); }',
      'void main() { Object value = <Object>[1]; print(\'before\'); value as List<int>; print(\'after\'); }',
      "void main() { dynamic value = 'wrong'; print('before'); int number = value; print('after'); }",
      "class C { C(); set value(int next) { print('setter'); } } dynamic value() { print('rhs'); return 'wrong'; } void main() { print('before'); C().value = value(); print('after'); }",
      "set target(int next) { print('setter'); } dynamic value() { print('rhs'); return 'wrong'; } void main() { print('before'); target = value(); print('after'); }",
      "class C { C(); int? get value { print('getter'); return null; } set value(int next) { print('setter'); } } dynamic bad() { print('rhs'); return 'wrong'; } void main() { print('before'); C().value ??= bad(); print('after'); }",
      "void main() { print('before'); int count = -1; 1 << count; print('after'); }",
      "void main() { print('before'); int count = -1; -1 >> count; print('after'); }",
      "void main() { print('before'); int count = -1; -1 >>> count; print('after'); }",
      '''
class C {
  C();
  void call(int positional, {required int named}) {}
}
C receiver() { print('receiver'); return C(); }
dynamic bad() { print('bad'); return 'wrong'; }
int later() { print('later'); return 2; }
void main() {
  print('before');
  receiver().call(named: bad(), later());
  print('after');
}
''',
      "void main() { List<Object> view = <int>[1]; print('before'); view[0] = 'wrong'; print('after'); }",
      "void main() { List<Object> view = <num>[1]; print('before'); view[0] = 'wrong'; print('after'); }",
      "void main() { List<Object> view = <int>[1]; print('before'); view.add('wrong'); print('after'); }",
      "void main() { List<Object> view = const<int>[1]; print('before'); view[9] = 'wrong'; print('after'); }",
      "void main() { List<Object> view = const<int>[1]; print('before'); view[9] = 2; print('after'); }",
      "void main() { var values = const[<int>[]]; print('before'); values[0].clear(); print('after'); }",
      "void main() { var values = <int>[]; print('before'); print(values[0]); }",
      "void main() { var values = <int>[1]; print('before'); print(values[-1]); }",
      "void main() { var values = <int>[1]; print('before'); values[1] = 2; print('after'); }",
      "int value() { print('rhs'); return 2; } void main() { var values = <int>[]; print('before'); values[0] = value(); print('after'); }",
      "void main() { var values = <int>[]; print('before'); values.removeLast(); print('after'); }",
      "void main() { var values = <int>[1, 2]; print('before'); for (final value in values) { values.clear(); print(value); } print('after'); }",
      "void main() { var values = <int>[1]; print('before'); for (final value in values) { if (value == 1) values.add(2); print(value); } print('after'); }",
      "void main() { var values = <int>[1]; print('before'); for (final value in values) { values.clear(); print(value); continue; } print('after'); }",
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
      'host.dart':
          'int hostRead(int value) => value + 4; '
          'int hostReadIfExists(int value) => value + 5; '
          'int hostCurrentDirectory(int value) => value + 6;',
      'properties.dart':
          'class Counter { int _value = 1; Counter(); int get value => _value; '
          'set value(int next) { _value = next; } int get _hidden => _value; '
          'set _hidden(int next) { _value = next; } }',
      'property-imports.dart':
          "import 'properties.dart' as p; void main() { var value = p.Counter(); "
          'value.value += 2; print(value.value); }',
      'top-accessor-storage.dart': 'int stored = 4;',
      'top-accessor-get.dart':
          "import 'top-accessor-storage.dart'; int get sharedAccess => stored; "
          'int get _hiddenTop => stored;',
      'top-accessor-set.dart':
          "import 'top-accessor-storage.dart'; set sharedAccess(int next) { stored = next; } "
          'set _hiddenTop(int next) { stored = next; }',
      'top-accessor-pair.dart':
          "export 'top-accessor-get.dart'; export 'top-accessor-set.dart';",
      'top-accessor-own-get.dart':
          "import 'top-accessor-storage.dart'; export 'top-accessor-set.dart'; "
          'int get sharedAccess => stored;',
      'top-accessor-own-set.dart':
          "import 'top-accessor-storage.dart'; export 'top-accessor-get.dart'; "
          'set sharedAccess(int next) { stored = next; }',
      'top-accessor-imports.dart':
          "import 'top-accessor-get.dart'; import 'top-accessor-set.dart'; "
          "import 'top-accessor-get.dart' as p show sharedAccess; "
          "import 'top-accessor-set.dart' as p show sharedAccess; "
          "import 'top-accessor-pair.dart' as both show sharedAccess; "
          "import 'top-accessor-own-get.dart' as ownGet; "
          "import 'top-accessor-own-set.dart' as ownSet; "
          'void main() { sharedAccess = 2; print(sharedAccess); '
          'p.sharedAccess += 3; print(p.sharedAccess); '
          'both.sharedAccess++; print(both.sharedAccess); '
          'ownGet.sharedAccess += 4; print(ownGet.sharedAccess); '
          'ownSet.sharedAccess++; print(ownSet.sharedAccess); }',
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
  print(hostReadIfExists(5));
  print(hostCurrentDirectory(5));
}
''',
      'metadata-notes.dart':
          'const note = <int>[1]; @note int value(int x) => x + 1;',
      'metadata-exports.dart': '@barrelNote export "metadata-notes.dart" show note, value; const barrelNote = 1;',
      'metadata-imports.dart':
          '@meta.note import "metadata-exports.dart" as meta show note, value; '
          '@meta.note void main() { print(meta.value(3)); }',
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
      'core-annotations-user.dart':
          'class pragma { final int code; const pragma(this.code); }',
      'core-annotations-export.dart':
          "export 'dart:core' show pragma, StringBuffer;",
      'core-annotations-combined.dart': "export 'dart:core' show pragma; export 'core-annotations-user.dart';",
      'core-annotations-imports.dart': r'''
import 'dart:core';
import 'dart:core' as core;
import 'core-annotations-user.dart';
import 'dart:core' as both show pragma;
import 'core-annotations-user.dart' as both;
import 'dart:core' as alias show pragma;
import 'core-annotations-export.dart' as alias;
import 'core-annotations-combined.dart' as combined;
const hint = core.pragma('OtherTool:hint', [1, true]);
@hint
@core.pragma('OtherTool:ignored')
@pragma(7)
@both.pragma(8)
@alias.pragma('OtherTool:alias')
void main() {
  print(pragma(7).code);
  print(both.pragma(8).code);
  print(combined.pragma(9).code);
  print(hint.name);
  print(hint.options);
  print(const alias.pragma('OtherTool:alias').options);
  print(identical(const core.pragma('OtherTool:same'),
      const alias.pragma('OtherTool:same')));
  var buffer = alias.StringBuffer();
  buffer.write('entry');
  print(buffer);
}
''',
      'core-annotations-implicit.dart':
          "import 'core-annotations-user.dart'; @pragma(7) void main() { "
          "var buffer = StringBuffer(); buffer.write(pragma(7).code); print(buffer); }",
      'core-annotations-own.dart':
          'const pragma = 7; @pragma void main() { print(pragma); }',
      'core-annotations-filtered.dart':
          "import 'dart:core' show print; import 'dart:core' as core show pragma; "
          "@core.pragma('OtherTool:hint') void main() { "
          "const hint = core.pragma('OtherTool:hint', 7); print(hint.name); print(hint.options); }",
      'nogc-values.dart': r'''
import 'dart:core';
import 'dart:core' as core;
const noGc = core.pragma('dartc:no-gc');
int pure(int value) => value + 1;
int even(int value) { if (value == 0) return 1; return odd(value - 1); }
int odd(int value) { if (value == 0) return 0; return even(value - 1); }
@noGc
int compute(int value) {
  print('nogc-static');
  return pure(value ~/ 3) + even(value & 7) + (value << (value & 63));
}
@core.pragma('dartc:no-gc')
Object box(bool value) => value;
@pragma('dartc:no-gc')
bool safe(String value, String suffix) => value.endsWith(suffix);
void main() { print(compute(65)); print(box(true)); print(box(false)); print(safe('a', 'long')); }
''',
      'nogc-user-annotation.dart': r'''
class pragma { final String name; const pragma(this.name); }
@pragma('dartc:no-gc')
List<int> allocated() => <int>[7];
void main() { print(allocated()); }
''',
      'version-old.dart': r'''
// @dart=3.6
int _ = 7;
int parameter(int _) => _;
int local() { int _ = 2; return _; }
int loop() { for (var _ in <int>[3]) return _; return 0; }
int separated() => 1_000;
''',
      'version-new.dart': r'''
// @dart=3.7
int _ = 7;
int parameter(int _) => _;
int local() { int _ = 2; return _; }
int loop() { for (var _ in <int>[3]) return _; return 0; }
int pair(int _, int _) => _;
''',
      'version-accessors.dart': r'''
// @dart=3.9
class Accessor { int get value => 1; set value(String next) {} }
int get value => 2;
set value(String next) {}
''',
      'version-private.dart': r'''
// @dart=3.12
class Secret {
  final int _value;
  Secret({this._value = 1});
  int read() => _value;
}
''',
      'version-flow.dart': r'''
// @dart=3.9
int assigned(int value) { int result; if (value != null) result = 1; return result; }
int unassigned(int value) { final int result; if (value == null) result = 1; result = 2; return result; }
''',
      'version-switch.dart': r'''
// @dart=3.0
int selected(bool value) {
  int result;
  switch (value) { case true: result = 1; break; case false: result = 2; break; }
  return result;
}
''',
      'version-imports.dart': r'''
// @dart=2.12
import 'version-old.dart' as old;
import 'version-new.dart' as modern;
import 'version-accessors.dart' as accessors;
import 'version-private.dart' as secret;
import 'version-flow.dart' as flow;
import 'version-switch.dart' as selection;
int nullFact(Null value) { int result; if (value == null) result = 4; return result; }
void main() {
  print(old.parameter(2)); print(old.local()); print(old.loop()); print(old.separated());
  print(modern.parameter(2)); print(modern.local()); print(modern.loop()); print(modern.pair(2, 3));
  List<List<List<int>>> nested = <List<List<int>>>[<List<int>>[<int>[7]]];
  print(nested[0][0][0]);
  var accessor = accessors.Accessor(); accessor.value = 'ignored'; print(accessor.value);
  accessors.value = 'ignored'; print(accessors.value);
  print(secret.Secret(value: 8).read());
  print(flow.assigned(1)); print(flow.unassigned(1));
  print(selection.selected(true)); print(selection.selected(false)); print(nullFact(null));
}
''',
      'version-header.dart': "#!/usr/bin/env dart\r\n/* header /* nested */ end */\r\n// @dart=2.14\r\n// @dart=3.14\r\nvoid main() { int value = -1; print(value >>> 63); value >>>= 63; print(value); }\r\n",
      'version-bom.dart': "\ufeff// @dart=3.6\nvoid main(){print(1_000);}\n",
      'version-named.dart': r'''
// @dart=2.17
class Arguments { final int first; final int last; const Arguments(this.first, {this.last = 0}); }
const arguments = Arguments(last: 4, 3);
int sum(int value, {int extra = 1}) => value + extra;
int trace = 0;
bool growable() { trace = trace * 10 + 1; return false; }
int length() { trace = trace * 10 + 2; return 2; }
int element() { trace = trace * 10 + 3; return 1; }
void main() { print(sum(extra: 2, 3)); print(arguments.first + arguments.last); print(List<int>.filled(growable: growable(), length(), element())); print(trace); }
''',
      'version-unnamed.dart': r'''
// @dart=2.19
library;
void main() { print(42); }
''',
      'version-markers.dart': r'''
/// @dart=3.5
// @dart=3.5.0
/* // @dart=3.5 */
import 'dart:core';
// @dart=3.5
void main() { print(1_000); }
''',
      'constant-values.dart': 'const values = <int>[1];',
      'constant-other.dart': 'const values = <int>[1];',
      'constant-imports.dart':
          "import 'constant-values.dart' as first; import 'constant-other.dart' as second; "
          "import 'dart:core'; import 'dart:core' as core; const local = <int>[1]; "
          'const same = core.identical(local, first.values); '
          'void main() { print(same); print(identical(local, second.values)); print(first.values == second.values); }',
      'const-class-first.dart': "class Item { final int value; const Item(this.value); } const item = Item(7);",
      'const-class-second.dart': "class Item { final int value; const Item(this.value); } const item = Item(7);",
      'const-class-exports.dart':
          "export 'const-class-first.dart' show Item, item;",
      'const-class-imports.dart': "import 'const-class-first.dart' as first; import 'const-class-exports.dart' as alias; import 'const-class-second.dart' as other; const value = first.Item(7); @alias.Item(7) void annotated() {} void main() { print(identical(value, alias.item)); print(identical(value, first.item)); print(identical(value, other.item)); print(value.value); }",
      'const-class-metadata-only.dart': "class UnusedTag { final int value; const UnusedTag(this.value); String toString() { print('unused metadata'); return 'tag'; } } const unused = UnusedTag(7); @unused void neverCalled() { print('never called'); } @UnusedTag(8) void main() { print(42); }",
      'const-class-finite-default.dart': "class C { final C? next; const C([this.next = const C(null)]); } void main() { const first = C(); const same = C(C(null)); print(identical(first, same)); print(first.next!.next); var one = C(); var two = C(); print(identical(one, two)); print(identical(one.next, two.next)); print(identical(one.next, first.next)); }",
    };
    for (final entry in libraries.entries) {
      File('${temporary.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    compare(File('${temporary.path}/imports.dart'), []);
    compare(File('${temporary.path}/core.dart'), []);
    compare(File('${temporary.path}/priority.dart'), []);
    compare(File('${temporary.path}/export-priority.dart'), []);
    compare(File('${temporary.path}/prefix-priority.dart'), []);
    compare(File('${temporary.path}/core-annotations-imports.dart'), []);
    compare(File('${temporary.path}/core-annotations-implicit.dart'), []);
    compare(File('${temporary.path}/core-annotations-own.dart'), []);
    compare(File('${temporary.path}/core-annotations-filtered.dart'), []);
    compare(File('${temporary.path}/nogc-values.dart'), []);
    compare(File('${temporary.path}/nogc-user-annotation.dart'), []);
    compare(File('${temporary.path}/version-imports.dart'), []);
    compare(File('${temporary.path}/version-header.dart'), []);
    compare(File('${temporary.path}/version-named.dart'), []);
    compare(File('${temporary.path}/version-unnamed.dart'), []);
    compare(File('${temporary.path}/version-markers.dart'), []);
    compare(File('${temporary.path}/version-bom.dart'), []);
    compare(File('${temporary.path}/constant-imports.dart'), []);
    compare(File('${temporary.path}/property-imports.dart'), []);
    compare(File('${temporary.path}/top-accessor-imports.dart'), []);
    compare(File('${temporary.path}/metadata-imports.dart'), []);
    compare(File('${temporary.path}/const-class-imports.dart'), []);
    compare(File('${temporary.path}/const-class-metadata-only.dart'), []);
    compare(File('${temporary.path}/const-class-finite-default.dart'), []);
    final rejected = [
      "@pragma('dartc:no-gc') int checked(String value,int index)=>value.codeUnitAt(index);void main(){print(checked('a',0));}",
      "@pragma('dartc:no-gc') int checked(String value)=>int.parse(value);void main(){print(checked('7'));}",
      "@pragma('dartc:no-gc') void checked(List<int> values){values.clear();}void main(){var values=<int>[1];checked(values);print(values.length);}",
      "\ufeff#!/usr/bin/env dart\n// @dart=3.6\nvoid main(){print(1_000);}\n",
      "// @dart=3.5\nvoid main(){print(1_000);}",
      // The accepted versioning specification permits tabs in a marker.
      "//\t@dart\t=\t3.5\nvoid main(){print(1_000);}",
      "// @dart=3.6\nvoid main(){int _=1;int _=2;}",
      "// @dart=3.6\nvoid f(int _,int _){}void main(){}",
      "// @dart=2.13\nvoid main(){print(1>>>1);}",
      "// @dart=2.16\nint f(int value,{int extra=0})=>value+extra;void main(){print(f(extra:2,3));}",
      "// @dart=2.16\nclass C{final int value;const C(this.value,{int ignored=0});}const c=C(ignored:2,3);void main(){}",
      "// @dart=2.18\nlibrary;void main(){}",
      "// @dart=3.14\nvoid main(){}",
      "// @dart=2.11\nvoid main(){}",
      "// @dart=3.8\nclass C{int get value=>1;set value(String next){}}void main(){}",
      "// @dart=3.8\nint get value=>1;set value(String next){}void main(){}",
      "// @dart=3.11\nclass C{int _value;C({this._value=1});}void main(){}",
      "// @dart=3.8\nint f(int value){int result;if(value!=null)result=1;return result;}void main(){print(f(1));}",
      "// @dart=2.12\nvoid f(int value){final int result;if(value==null)result=1;result=2;print(result);}void main(){f(1);}",
      "// @dart=2.19\nint f(bool value){int result;switch(value){case true:result=1;break;case false:result=2;break;}return result;}void main(){print(f(true));}",
      "void f(int value){final int result;if(value is String)result=1;result=2;print(result);}void main(){f(1);}",
      "import 'dart:core'; import 'dart:core' as core; List<int> helper() => <int>[1]; @core.pragma('dartc:no-gc') List<int> bad() => helper(); void main() {}",
      "const noGc = pragma('dartc:no-gc'); void helper([List<int> values = const <int>[1]]) {} @noGc void bad() { helper(); } void main() {}",
      "Object value = 1; @pragma('dartc:no-gc') Object bad() => value; void main() {}",
      "@pragma('dartc:no-gc') int bad(dynamic value) => value as int; void main() {}",
      "@pragma('dartc:no-gc') int bad(int value, int other) => (value ~/ other) + (value << other); void main() {}",
      "@pragma('dartc:may-gc') int helper(int value) => value; @pragma('dartc:no-gc') int bad() => helper(1); void main() {}",
      "@pragma('dartc:no-gc') int value = 0; void main() {}",
      "@pragma('dartc:no-gc', true) void bad() {} void main() {}",
      "import '$standard' as rt; @pragma('dartc:no-gc') int bad(int target) => rt.nativeCall0(target); void main() {}",
      "import '$standard' as rt; @pragma('dartc:no-gc') int bad(int bytes) => rt.rtAlloc(bytes); void main() {}",
      "import '$standard' as rt; @pragma('dartc:no-gc') int bad(int type) => rt.rtListNew(type); void main() {}",
      "import 'dart:core' hide pragma; @pragma('OtherTool:hint') void main() {}",
      "import 'dart:core' as core; @pragma('OtherTool:hint') void main() {}",
      "import 'dart:core' as core; @core.pragma(7) void main() {}",
      r"class C { final int value; const C(this.value); } const object = C(1); const text = '$object'; void main() {}",
      r"class C { final int value; const C(this.value); int get hashCode => value; } const same = C(1) == C(1); void main() {}",
      "class C { int value = 1; const C(); } void main() {}",
      "class C { const C() {} } void main() {}",
      "class C { const C() => 1; } void main() {}",
      "class C { final int value; const C(); } void main() {}",
      "class C { final int value = 1; const C(this.value); } void main() {}",
      "class C { final List<int> values = []; const C(); } void main() {}",
      "class C { final List<int> values; const C([this.values = []]); } void main() {}",
      "int value() => 1; class C { final int field = value(); const C(); } void main() {}",
      "class C { final int value; C(this.value); } const object = C(1); void main() {}",
      "class C { final int value; const C(this.value); } int value = 1; const object = C(value); void main() {}",
      "class C { final int value; const C(this.value); } const object = C(\"wrong\"); void main() {}",
      "const value = const identical(1, 1); void main() {}",
      "@identical(1, 1) void main() {}",
      "class C { final C? next; const C([this.next = const C()]); } void main() {}",
      "const value = 1; class Mark { final int id; const Mark(this.id); } class C { int value = 2; C(); @Mark(value) void f() {} } void main() {}",
      "const value = 1; class Mark { final int id; const Mark(this.id); } class C { int value = 2; C(); void f() { const mark = Mark(value); print(mark); } } void main() {}",
      "const value = 1; class Mark { final int id; const Mark(this.id); } class C { int value = 2; final Mark mark = const Mark(value); C(); } void main() {}",
      '@missing void main() {}',
      'int get note => 1; @note void main() {}',
      'void main() { @note int value = 1; const note = 2; print(value); }',
      'const note = 1; void f(int note) { @note int value = 2; print(value); } void main() { f(3); }',
      'const note = 1; class C { int note = 2; C(); @note void f() {} } void main() { C().f(); }',
      'const note = 1; void main() { for (@note var note in <int>[2]) print(note); }',
      'const note = "text"; @note.length void main() {}',
      'const void note = 1; @note void main() {}',
      'import "metadata-exports.dart" as meta hide note; @meta.note void main() {}',
      'import "metadata-notes.dart" as meta; void main() { const meta = 1; @meta.note int value = 2; print(value); }',
      'int f() => 1; void main() { print(f<int>()); }',
      'void main() { print<int>(1); }',
      'void main() { List<int>.filled<int>(1, 0); }',
      'void main() { List<int, String>.filled(2, 1); }',
      'void main() { <int>[].add<int>(1); }',
      'const same = identical<int>(1, 1); void main() { print(same); }',
      'class C { int value = 1; C(); } void main() { var value = C(); print(value<int>.value); }',
      'void f(Never value) { value.foo(x: 1, x: 2); } void main() {}',
      'void f(Never value) { value.foo<Missing>(); } void main() {}',
      'void noop() {} void f(Never value) { value[noop()]; } void main() {}',
      'class C { C(); void change() { this = C(); } } void main() {}',
      "import 'exports.dart'; void main() { print(hidden()); }",
      "import 'math.dart'; void main() { print(_private()); }",
      "import 'properties.dart' as p; void main() { var value = p.Counter(); value._hidden = 2; }",
      "import 'top-accessor-set.dart'; int get sharedAccess => 9; void main() { sharedAccess = 2; }",
      "import 'top-accessor-get.dart'; set sharedAccess(int next) {} void main() { print(sharedAccess); }",
      "import 'top-accessor-pair.dart' as p hide sharedAccess; void main() { p.sharedAccess = 2; }",
      "import 'top-accessor-pair.dart' as p hide sharedAccess; void main() { print(p.sharedAccess); }",
      "import 'top-accessor-pair.dart' as p; void main() { p._hiddenTop = 2; }",
      "import 'dart:core' hide print; void main() { print(1); }",
      "import 'math.dart' deferred as math; void main() {}",
      "import 'dart:math'; void main() {}",
      'void main() { dynamic source = 1; int slot = 0; var values = [slot = source]; List<int> typed = values; print(typed); }',
      'void value() { return 7; } void main() { value(); }',
      'void value() {} void main() { dynamic result = value(); print(result); }',
      'void value() => 7; void main() { print(value() is int); }',
      'void noop() {} void main() { noop()!; }',
      'void main() { final int? value; print(value!); }',
      'void main() { int? value = 1; value! += 2; }',
      'void take([int value = 1!]) {} void main() { take(); }',
      'void main() { void value = 7; value as dynamic; print(value); }',
      'void main() { void value = 7; value as Object?; print(value); }',
      'void value() {} void main() { value() ?? 1; }',
      'void value() {} void main() { dynamic source = 1; var values = [source ?? value()]; print(values[0]); }',
      'void main() { int value; print(1 ?? value); }',
      'class C { C(); int get value => 1; } void main() { C().value ??= 2; }',
      'class C { C(); set value(int next) {} } void main() { C().value ??= 2; }',
      'void main() { final int value = 1; value ??= 2; }',
      "void main() { int value = 1; value ??= 'wrong'; }",
      'void main() { int value = 1; int missing; value ??= missing; }',
      'void touch() {} void main() { dynamic value; value ??= touch(); }',
      'void f(int? value) { int assigned; value ??= (assigned = 1); print(assigned); } void main() { f(2); }',
      'void f(int? value) { final int assigned; value ??= (assigned = 1); assigned = 2; } void main() { f(2); }',
      'void main() { final int value = 1; value = 2; print(value); }',
      'void main() { final int value = 1; print(++value); }',
      'void main() { final int value; value = (value = 1); print(value); }',
      'void main() { final int value; return; if (true) value = 1; value = 2; print(value); }',
      'void f(bool flag) { final int value; return; if (flag) value = 1; value = 2; print(value); } void main() { f(true); }',
      'final int value = 1; void main() { value = 2; print(value); }',
      'final int? value; void main() { print(value); }',
      'int value; void main() { print(value); }',
      'class C { final int value; C(this.value); } void main() { var object = C(1); object.value += 2; }',
      'class C { C(); set value() {} } void main() {}',
      'class C { C(); set value([int next = 1]) {} } void main() {}',
      'class C { C(); set value({required int next}) {} } void main() {}',
      'class C { C(); int set value(int next) { return next; } } void main() {}',
      'class C { C(); int get value => 1; } void main() { C().value = 2; }',
      'class C { C(); set value(int next) {} } void main() { C().value += 2; }',
      'class C { int value = 1; C(); set value(int next) {} } void main() {}',
      'class C { C(); int value() => 1; int get value => 2; } void main() {}',
      'class C { C(); int get value => 1; set value(int next) {} } void main() { dynamic next = 2; C().value += next; }',
      'int get value => 1; int get value => 2; void main() {}',
      'set value(int next) {} set value(int next) {} void main() {}',
      'int value = 1; set value(int next) {} void main() {}',
      'int value() => 1; set value(int next) {} void main() {}',
      'int get value => 1; void main() { value = 2; }',
      'set value(int next) {} void main() { print(value); }',
      'int get value => 1; set value(int next) {} void main() { dynamic next = 2; value += next; }',
      'class C { const int value = 1; C(); } void main() { print(C().value); }',
      'class C { final int? value; } void main() { print(C().value); }',
      'class C { int value; C(); } void main() { print(C().value); }',
      'class C { final int value = 1; C(this.value); } void main() { print(C(2).value); }',
      'void main() { final int? value; print(value); }',
      'void f(bool flag) { final int value; if (flag) value = 1; value = 2; print(value); } void main() { f(false); }',
      'void main() { final int value; for (int i = 0; i < 2; i++) { value = i; } }',
      'void main() { final int value; do { value = 1; } while (false); print(value); }',
      'int value() {} void main() { print(value()); }',
      'int value(bool flag) { if (flag) return 1; } void main() { print(value(false)); }',
      'int value = 2; const selected = 1 ?? value; void main() { print(selected); }',
      "void main() { var values = [1 ?? 'other']; List<int> narrow = values; print(narrow); }",
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
      'void main() { int value; if (false) print(value); }',
      'void f(bool flag) { int value; if (flag) return; else { value = 1; return; } print(value); } void main() { f(false); }',
      "void f(Object value) { if (value is String) { while (value.length > 0) { value = 's'; break; } } } void main() { f('s'); }",
      'void main() { Object value = 1; var values = [value]; List<int> typed = values; print(typed); }',
      'void f(int? value) { if (value == null) { var values = [value]; List<Null> typed = values; print(typed); } } void main() { f(null); }',
      'void f(int value) { int result; switch (value) { case 1: result = 1; break; default: } print(result); } void main() { f(2); }',
      'void main() { Object value = 1; int number = value; print(number); }',
      'void take(int value) {} void f(int? value) { take(value); } void main() { f(1); }',
      'int f(Object? value) => value; void main() { print(f(1)); }',
      'void f(bool? value) { if (value) print(1); } void main() { f(true); }',
      "void f(String? value) { print(value.length); } void main() { f('s'); }",
      'void f(List<int>? value) { print(value[0]); } void main() { f(<int>[1]); }',
      'void f(int? value) { print(-value); } void main() { f(1); }',
      'void f(int? value) { print(1 + value); } void main() { f(1); }',
      'void f(Object value, dynamic other) { print(value + other); } void main() { f(1, 2); }',
      'void main() { int value = 1; dynamic other = 2; value += other; print(value); }',
      'void main() { List<num> values = <num>[1]; List<int> narrow = values; print(narrow); }',
      'void call({required int value}) {} void main() { call(); }',
      'void call({int value = 1}) {} void main() { call(value: 1, value: 2); }',
      'void call({int value = 1}) {} void main() { call(other: 2); }',
      'void call(int value) {} void main() { call(value: 1); }',
      'void call(int value, [int other = 1]) {} void main() { call(); }',
      'void call([int value = 1]) {} void main() { call(1, 2); }',
      'void call([int value]) {} void main() {}',
      'void call({required int value = 1}) {} void main() {}',
      'void call([int value = 1], {int other = 2}) {} void main() {}',
      'class C { int value; C({required this.value}); } void main() { C(); }',
      'class C { int _x; C({this._x = 1, int x = 2}); } void main() {}',
      'int value = 1; void call([int argument = value]) {} void main() { call(2); }',
      'int value = 1; void call([int argument = true ? 1 : value]) {} void main() {}',
      "const dynamic value = 'wrong'; void call([int argument = value]) {} void main() { call(2); }",
      'void call([List<int> values = []]) {} void main() { call(); }',
      'int value = 1; const values = [value]; void main() { print(values); }',
      'const Object value = 1; const values = <int>[value]; void main() { print(values); }',
      "const dynamic value = 'wrong'; const values = <int>[value]; void main() { print(values); }",
      'const int value = 1; void call(int value) { const values = [value]; print(values); } void main() { call(2); }',
      'void main() { const values = [1]; values = <int>[2]; print(values); }',
      'bool identical(Object? left, Object? right) => true; const same = identical(1, 1); void main() { print(same); }',
      "void main() { print('abc'.codeUnitAt()); }",
      "void main() { print('abc'.substring()); }",
      "void main() { print('abc'.endsWith('c', 1)); }",
      'void main() { print(String.fromCharCodes(<int>[65], 0)); }',
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
    for (final literal in ['1_', '0x_FF', '0_xFF']) {
      final invalid = File('${temporary.path}/separator-$literal.dart')
        ..writeAsStringSync('void main() { print($literal); }');
      final expected = Process.runSync(sdk, [invalid.path]);
      if (expected.exitCode == 0) {
        throw StateError('Expected SDK rejection for ${invalid.path}.');
      }
      reject(invalid, diagnostic: 'digit separator');
    }
    final core = Directory('${temporary.path}/std/core')
      ..createSync(recursive: true);
    for (final name in ['string_buffer.dart', 'annotations.dart']) {
      File('${File(standard).parent.path}/std/core/$name')
          .copySync('${core.path}/$name');
    }
    File('${File(standard).parent.path}/std/core.dart')
        .copySync('${temporary.path}/std/core.dart');
    final empty = File('${temporary.path}/empty.dart')
      ..writeAsStringSync('void main() {}');
    final emptyRuntime = File('${temporary.path}/runtime-empty.dart')
      ..writeAsStringSync('const int rtAbiVersion = $runtimeAbiVersion;');
    final emptyExecutable = '${empty.path}.out';
    run(
      driver,
      compileArguments(empty, emptyExecutable, emptyRuntime.path),
      native: compiler != null,
    );
    if (run(emptyExecutable, [], native: true).stdout != '') {
      throw StateError(
        'Empty program with no runtime storage produced output.',
      );
    }
    final eagerRuntime = File('${temporary.path}/runtime-eager.dart')
      ..writeAsStringSync(
        'const int rtAbiVersion = $runtimeAbiVersion;\n' +
            r'''external int nativeTarget();
external int nativeSyscall(int n, int a, int b, int c, int d, int e, int f);
int zero = 0;
bool flag = false;
int calls = 0;
int first = changeLater();
int later = 0;
int effect = returnZero();
int changeLater() { calls++; later = 7; return 1; }
int returnZero() { calls++; effect = 9; return 0; }
void verify() {
  var status = 0;
  if (zero != 0 || flag || calls != 2 || first != 1 || later != 0 || effect != 0)
    status = 73;
  var syscall = 1;
  if (nativeTarget() == 1) syscall = 93;
  nativeSyscall(syscall, status, 0, 0, 0, 0, 0);
}
''',
      );
    final eager = File('${temporary.path}/eager.dart')
      ..writeAsStringSync(
        "import 'runtime-eager.dart' as rt; void main() { rt.verify(); }",
      );
    final eagerExecutable = '${eager.path}.out';
    run(
      driver,
      compileArguments(eager, eagerExecutable, eagerRuntime.path),
      native: compiler != null,
    );
    if (run(eagerExecutable, [], native: true).stdout != '') {
      throw StateError('Eager scalar initialization produced output.');
    }
    final invalidRuntimes = [
      'const int rtAbiVersion = $runtimeAbiVersion; external int nativeLoad64(int pointer, int extra);',
      'const int rtAbiVersion = $runtimeAbiVersion; external bool nativeTarget();',
      "const int rtAbiVersion = $runtimeAbiVersion; external int nativeLoad64(int pointer); int invalid() => nativeLoad64('wrong');",
      'const int rtAbiVersion = $runtimeAbiVersion; external int nativeMetadataAddress(int first, int second);',
      'const int rtAbiVersion = $runtimeAbiVersion; external int nativeMetadataAddress();',
      'const int rtAbiVersion = ${runtimeAbiVersion - 1};',
      'int rtAbiVersion = $runtimeAbiVersion;',
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
  if (args.length > 1) {
    if (args[1] == 'cwd')
      print(hostCurrentDirectory());
    else {
      print('before');
      print(hostReadIfExists(args[0]));
    }
    return;
  }
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
  print(hostReadIfExists(args[0] + 'utf8'));
  print(hostReadIfExists(args[0] + 'missing') == null);
  print(hostReadIfExists(args[0] + '0')!.isEmpty);
  print(hostReadIfExists(args[0] + '0/child') == null);
  print(hostCurrentDirectory());
}
''',
      );
    final outputPrefix = '${temporary.path}/io-你好🙂-';
    compare(
      io,
      [outputPrefix],
      outputs: [
        for (var i = 0; i < 6; i++) '$outputPrefix$i',
        '${outputPrefix}utf8',
      ],
    );
    final cwd = Directory('${temporary.path}/cwd-你好🙂 %')..createSync();
    final ioExecutable = '${io.path}.out';
    for (final directory in [
      cwd,
      if (Platform.isLinux)
        Directory(
          '${cwd.path}/${List.filled(32, 'directory-with-a-long-component-你好🙂').join('/')}',
        )..createSync(recursive: true),
    ]) {
      final expected = Process.runSync(sdk, [
        io.path,
        outputPrefix,
        'cwd',
      ], workingDirectory: directory.path);
      final actual = Process.runSync(
        ioExecutable,
        [outputPrefix, 'cwd'],
        workingDirectory: directory.path,
        environment: {
          'PATH': '/usr/bin:/bin',
          'PWD': '/not-the-working-directory',
        },
        includeParentEnvironment: false,
      );
      if (expected.exitCode != 0 ||
          actual.exitCode != 0 ||
          actual.stdout != expected.stdout) {
        throw StateError(
          'Native working directory differs: '
          '${expected.stdout}${expected.stderr}${actual.stdout}${actual.stderr}',
        );
      }
    }
    final directoryRead = Process.runSync(
      ioExecutable,
      [cwd.path, 'read'],
      environment: {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    if (directoryRead.exitCode != 74 ||
        directoryRead.stdout != 'before\n' ||
        !directoryRead.stderr.toString().contains(cwd.path)) {
      throw StateError(
        'Optional reading treated an I/O error as missing: '
        '${directoryRead.stdout}${directoryRead.stderr}',
      );
    }
    for (final body in [
      "void main() { String value = hostReadIfExists('missing'); print(value); }",
      'void main() { hostReadIfExists(1); }',
      'void main() { hostReadIfExists(); }',
      "void main() { hostCurrentDirectory('extra'); }",
      "@pragma('dartc:no-gc') String? read(String path) => hostReadIfExists(path); void main() {}",
      "@pragma('dartc:no-gc') String cwd() => hostCurrentDirectory(); void main() {}",
    ]) {
      final invalid = File('${temporary.path}/invalid-host.dart')
        ..writeAsStringSync(
          "import '${File(standard).parent.path}/host.dart';\n$body",
        );
      reject(invalid);
    }
    stdout.writeln('Behavior matches official Dart.');
  } on ProcessException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
