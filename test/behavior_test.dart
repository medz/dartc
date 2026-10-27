import 'dart:convert';
import 'dart:io';

import '../lib/src/layout.dart';
import '../tool/src/process.dart';

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

int localTrace = 0;
int localStep(int value) { localTrace = localTrace * 10 + value; return value; }
localTopResult() => 1;
void localOpaque() => 9223372036854775807;

int Function(int) localFactory() {
  const offsets = <int>[3];
  int plus(int value) => value + offsets[0];
  next(int value) => plus(value) + 1;
  int Function(int) select() => next;
  return select();
}

void localFunctions() {
  int factorial(int value) => value < 2 ? 1 : value * factorial(value - 1);
  int sameName(int sameName) => sameName + 1;
  print(factorial(5));
  print(sameName(4));
  {
    int factorial(int value) => value + 3;
    print(factorial(2));
  }
  const bias = 7;
  int optional([int value = bias]) => value;
  named(int value, {int extra = bias, int last = 3}) => value + extra + last;
  print(optional());
  print(named(last: localStep(1), localStep(2), extra: localStep(3)));
  print(localTrace);
  print([named(4)] is List<int>);
  int packed(int a,int b,int c,int d,int e,int f,int g,int h,{int i=9}) => a+i;
  print(packed(1,2,3,4,5,6,7,8));
  @pragma('dartc:no-gc') int safe(int value) => value + 1;
  print(safe(7));
  var callback = localFactory();
  print(callback(5));
  print(<int Function(int)>[callback][0](3));
  localResult() => 1;
  blockResult() { return 1; }
  print([localTopResult()] is List<int>);
  print([localResult()] is List<int>);
  print([blockResult()] is List<int>);
  recursive(int value) => value == 0 ? 1 : recursive(value - 1);
  print([recursive(2)] is List<int>);
  nothing() {}
  forever() { while (true) {} }
  deadReturn() { if (false) return 'dead'; return 1; }
  nested() { hidden() => 7; return 'outer'; }
  listResult(bool flag) { if (flag) return []; return [1]; }
  nullable(bool flag) { if (flag) return 1; }
  opaque() => localOpaque();
  print([nothing()] is List<Null>);
  print(forever is Never Function());
  print([deadReturn()] is List<int>);
  print([nested()] is List<String>);
  print(listResult(false) is List<int>);
  print([nullable(true)] is List<int?>);
  print(<void>[opaque()]);
  Probe identity(Probe value) { int Probe = 0; return value; }
  Probe byName(Probe Probe) => Probe;
  print(identity(Probe(3)).value);
  print(byName(Probe(4)).value);
  var total = 0;
  repeat:
  for (var i = 0; i < 3; i++) {
    value() => 1;
    total += value();
    if (i < 2) continue repeat;
    break repeat;
  }
  print(total);
  if (true) int inIf() => 1;
  declared: int labeled() => 2;
  while (false) int inLoop() => 3;
  print(labeled());
}

int Function(int) anonymousGlobal=(value)=>value+1;
var anonymousMixed=(bool choose)=>choose?[1]:['s'];
var anonymousNested=(bool choose)=>choose?[[1]]:[['s']];
List<Object> Function() anonymousTyped=()=>[1];
int anonymousTrace=0;
int anonymousStep(int value){anonymousTrace=anonymousTrace*10+value;return value;}
int anonymousApply(int Function(int) callback)=>callback(5);
class AnonymousBox {
  int Function(int) field=(value)=>value+2;
  final int Function(int) supplied;
  AnonymousBox(this.supplied);
}
void anonymousFunctions(){
  var empty=()=>7;
  var untyped=(value)=>value;
  int Function(int) contextual=(value)=>value;
  print([empty()] is List<int>);
  print([untyped(1)] is List<int>);
  print([contextual(1)] is List<int>);
  var fresh=()=>[1];
  print(anonymousMixed(true) is List<int>);
  print(anonymousNested(true) is List<List<int>>);
  print(anonymousTyped() is List<int>);print(fresh() is List<int>);
  print(anonymousApply((value)=>value+2));
  print(anonymousGlobal(8));
  var box=AnonymousBox((value)=>value+3);
  print(box.field(4));print(box.supplied(4));
  int Function(int) Function() factory=()=>((value)=>value+2);
  print(factory()(5));
  var local=(){int plus(int value)=>value+1;return plus;};
  print(local()(4));
  var direct=(int value){return value+1;}(5);
  print(direct);
  print((([int value=4])=>value)());
  print((([int value=4])=>value).call());
  print(((int first,{int extra=2})=>first+extra).call(extra:3,2));
  print(((int first,{int extra=2,int last=3})=>first+extra+last)(
    last:anonymousStep(1),anonymousStep(2),extra:anonymousStep(3)));
  print(anonymousTrace);
  void Function() opaque=()=>9223372036854775807;
  print(<void>[opaque()]);
}

typedef CapturedRead = int Function();
typedef CapturedStep = int Function(int);
CapturedRead capturedCounter(int initial) {
  var value=initial;
  int next()=>++value;
  print(identical(next,next));
  return next;
}
List<CapturedRead> capturedPair() {
  var value=0;
  int next()=>++value;
  int read()=>value;
  return [next,read];
}
CapturedRead capturedChain(int initial) {
  var value=initial;
  CapturedRead middle(){int next()=>++value;return next;}
  return middle();
}
CapturedStep capturedRecursive(int base) {
  int next(int value) {
    CapturedStep self=next;
    return value==0?base:(value%2==0?next(value-1):self(value-1))+1;
  }
  return next;
}
class CapturedObject {
  int value;
  CapturedObject(this.value);
  CapturedRead increment()=>()=>++value;
  CapturedRead read()=>()=>this.value;
  CapturedRead shadow(int value)=>()=>value;
}
class CapturedInitializer {
  int value;
  final CapturedRead read;
  CapturedInitializer(this.value):read=(()=>value);
  CapturedInitializer.parameter(int input):value=0,read=(()=>input);
}
void capturedFunctions() {
  var first=capturedCounter(1),second=capturedCounter(10);
  print(first());print(first());print(second());
  var pair=capturedPair();print(pair[0]());print(pair[1]());
  var chained=capturedChain(3);print(chained());print(chained());
  print(capturedRecursive(10)(3));
  var object=CapturedObject(4);
  var increment=object.increment(),read=object.read();
  print(increment());print(read());print(object.shadow(9)());
  var initialized=CapturedInitializer(7);initialized.value=9;print(initialized.read());
  print(CapturedInitializer.parameter(8).read());
  Object stable=7;if(stable is int){int readStable()=>stable+1;print(readStable());}
  var declared=<CapturedRead>[];
  for(var i=0;i<3;i++){declared.add(()=>i);}
  print(declared[0]());print(declared[1]());print(declared[2]());
  var external=<CapturedRead>[];
  var index=0;
  for(index=0;index<3;index++){external.add(()=>index);}
  print(external[0]());print(external[1]());print(external[2]());
  var elements=<CapturedRead>[];
  for(var value in<int>[2,4,6]){elements.add(()=>value);}
  print(elements[0]());print(elements[1]());print(elements[2]());
  int? nullable=3;int nullableRead()=>nullable??0;
  nullable=null;print(nullableRead());
  String text='before';String readText()=>text;
  text='after';print(readText());
  Object value=7;
  int promoted(){if(value is int)return value+1;return -1;}
  print(promoted());value='changed';print(promoted());
  var base=10;
  int packed(int a,int b,int c,int d,int e,int f,int g,int h)=>base+a+h;
  var callback=packed;print(callback(1,2,3,4,5,6,7,8));
  base=20;print(packed(1,2,3,4,5,6,7,8));
}

void main(List<String> args) {
  listContexts();
  localFunctions();
  anonymousFunctions();
  capturedFunctions();
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

Future<void> main(List<String> args) async {
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
  final sdk = Platform.resolvedExecutable;
  final driver = compiler ?? sdk;
  final processes = <ProcessOutcome>[];
  final identities = <String, Object?>{
    'sdk': {'executable': sdk, 'version': Platform.version},
    'compiler': {
      'executable': driver,
      'source': compiler == null ? '$root/bin/dartc.dart' : null,
    },
    'runtime': {'path': standard, 'expectedAbi': runtimeAbiVersion},
  };
  var succeeded = false;

  Future<ProcessOutcome> capture(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final result = await captureProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    );
    processes.add(result);
    if (result.startError != null ||
        result.captureError != null ||
        result.timedOut ||
        result.outputLimited ||
        result.exitCode == null) {
      throw StateError(
        'Process capture failed: $executable $arguments '
        '(timeout=${result.timedOut}, outputLimited=${result.outputLimited}, '
        'start=${result.startError}, capture=${result.captureError})',
      );
    }
    return result;
  }

  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    bool native = false,
    String? workingDirectory,
  }) async {
    final result = await capture(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: native ? {'PATH': '/usr/bin:/bin'} : null,
      includeParentEnvironment: !native,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stdout}${result.stderr}',
        result.exitCode!,
      );
    }
    return result;
  }

  try {
    final hash = await run(
      Platform.isMacOS ? '/usr/bin/shasum' : '/usr/bin/sha256sum',
      [
        if (Platform.isMacOS) '-a',
        if (Platform.isMacOS) '256',
        compiler ?? '$root/bin/dartc.dart',
        standard,
      ],
    );
    identities['sha256'] = hash.stdout;

    final source = File('${temporary.path}/program.dart')
      ..writeAsStringSync(program);
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
    List<String> sdkOptions(List<String> options) =>
        options.length == 2 && options[0] == '--packages'
        ? ['--packages=${options[1]}']
        : options;
    Future<void> compare(
      File source,
      List<String> arguments, {
      List<String> outputs = const [],
      List<String> options = const [],
      String? workingDirectory,
    }) async {
      final executable = '${source.path}.out';
      for (final path in outputs) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      final expected = await run(sdk, [
        ...sdkOptions(options),
        source.path,
        ...arguments,
      ], workingDirectory: workingDirectory);
      final expectedFiles = [
        for (final path in outputs) File(path).readAsBytesSync(),
      ];
      for (var i = 0; i < outputs.length; i++) {
        File('${outputs[i]}.sdk').writeAsBytesSync(expectedFiles[i]);
      }
      await run(
        driver,
        [...compileArguments(source, executable), ...options],
        native: compiler != null,
        workingDirectory: workingDirectory,
      );
      for (final path in outputs) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      final actual = await run(
        executable,
        arguments,
        native: true,
        workingDirectory: workingDirectory,
      );
      if (base64Encode(actual.stdoutBytes) !=
              base64Encode(expected.stdoutBytes) ||
          base64Encode(actual.stderrBytes) !=
              base64Encode(expected.stderrBytes)) {
        throw StateError(
          '${source.path} differs from official Dart.\n'
          'Expected stdout:\n${expected.stdout}\nActual stdout:\n${actual.stdout}\n'
          'Expected stderr:\n${expected.stderr}\nActual stderr:\n${actual.stderr}',
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

    await compare(source, ['alpha', '你好']);
    final values = File('${temporary.path}/values.dart')
      ..writeAsStringSync(
        File('$root/test/fixtures/values.dart').readAsStringSync(),
      );
    await compare(values, [for (var i = 0; i < 20; i++) '参数$i🙂']);
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
    await run(
      driver,
      compileArguments(roots, rootsExecutable),
      native: compiler != null,
    );
    final rootOutput = (await run(rootsExecutable, [
      'alpha',
      '你好🙂',
    ], native: true)).stdout;
    if (rootOutput != 'roots ok\n') {
      throw StateError(
        'Unexpected native root enumeration output: $rootOutput',
      );
    }
    final exhaustedRoots = await capture(
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
    await compare(namedEntry, ['ignored', '你好']);
    final twoEntry = File('${temporary.path}/two-entry.dart')
      ..writeAsStringSync(
        "void main(List<String> args, [Object? message = 'default', int third = 3]) { "
        'print(args); print(message); print(third); }',
      );
    await compare(twoEntry, ['alpha', '你好🙂']);
    final invalidEntry = File('${temporary.path}/invalid-entry.dart')
      ..writeAsStringSync(
        "void main(List<String> args, [int second = 1]) { print('body'); }",
      );
    final expectedEntry = await capture(sdk, [invalidEntry.path]);
    final entryExecutable = '${invalidEntry.path}.out';
    await run(
      driver,
      compileArguments(invalidEntry, entryExecutable),
      native: compiler != null,
    );
    final actualEntry = await capture(
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
      "class C{int call(int value)=>value;}void main(){dynamic value=C();print('before');int Function(int) f=value;print(f(1));}",
      "class C{int call(int value)=>value;}void main(){print('before');print(C() as Function);}",
      "class C{int call(int value){print('body');return value;}}dynamic bad(){print('argument');return 'wrong';}void main(){print('before');print(C()(bad()));}",
      "class C{int read(int value){print('body');return value;}}void main(){dynamic value=C().read;print('before');String Function(int) wrong=value;print(wrong(1));}",
      "class C{int read(int value){print('body');return value;}}dynamic bad(){print('argument');return 'wrong';}void main(){var callback=C().read;print('before');print(callback(bad()));}",
      "class C{int read()=>1;}C? missing()=>null;int argument(){print('argument');return 0;}void main(){var callback=missing()?.read;print('before');print(callback!());print(argument());}",
      "dynamic bad(){print('value');return 'wrong';}int tail(){print('tail');return 2;}void main(){print('before');print(<int>[?bad(),tail()]);}",
      "void main(){dynamic values=<Object>[1,'bad'];print('before');print([for(int i in values) i]);}",
      "int tail(){print('tail');return 3;}void main(){dynamic values=<Object>[1,'bad'];print('before');print(<int>[...values,tail()]);}",
      "void main(){dynamic values=3;print('before');print([...values]);}",
      "void main(){dynamic values=null;print('before');print([...values]);}",
      "void main(){var values=[1,2];print('before');print([for(var i in values) (values..clear()).length]);}",
      'class C{int value=1;}C? missing(){print("receiver");return null;}void main(){print("before");print((missing()?.value)!);}',
      'class C{C? child;}void main(){print("before");print(C()?.child!.child);}',

      "class C { static set value(int next) { print('setter'); } } dynamic bad() { print('rhs'); return 'wrong'; } void main() { print('before'); C.value = bad(); }",
      "dynamic redirectedArgument() { print('rhs'); return 'wrong'; } class C { final int value; C.base(this.value) { print('body'); } C(dynamic value):this.base(value); } void main() { print('before'); C(redirectedArgument()); }",
      "dynamic badInitializer() { print('rhs'); return 'wrong'; } class C { final int value; C():value=badInitializer() { print('body'); } } void main() { print('before'); C(); }",
      "typedef F=int Function(int); String wrong(int value)=>'wrong'; int argument(){print('argument');return 1;} void main(){print('before');dynamic source=wrong;F callback=source;print(callback(argument()));}",
      "typedef F=int Function(int); int argument(){print('argument');return 1;} void main(){print('before');dynamic source=1;F callback=source;print(callback(argument()));}",
      "typedef F=int Function(int); int argument(){print('argument');return 1;} void main(){F? callback;print('before');callback!(argument());}",
      "typedef F=int Function(int); int value(int x)=>x; String wrong(int x)=>'wrong'; void main(){List<Function> callbacks=<F>[value];print('before');callbacks[0]=wrong;print('after');}",
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
      "void main() { var buffer = StringBuffer('kept'); print('before'); buffer.writeCharCode(-1); print('after'); }",
      "void main() { var buffer = StringBuffer('kept'); print('before'); buffer.writeCharCode(1114112); print('after'); }",
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
      "List<int> receiver() { print('receiver'); return <int>[1]; } int index() { print('index'); return -1; } void main() { print('before'); receiver().removeAt(index()); print('after'); }",
      "void main() { var values = <int>[1]; print('before'); values.removeAt(1); print('after'); }",
      "void main() { var values = List<int>.filled(1, 1); print('before'); values.removeAt(-1); print('after'); }",
      "void main() { print('before'); const <int>[].removeAt(0); print('after'); }",
      "dynamic index() { print('index'); return 'wrong'; } void main() { print('before'); const <int>[1].removeAt(index()); print('after'); }",
      "List<int> receiver() { print('receiver'); return <int>[]; } int index() { print('index'); return 1; } int element() { print('element'); return 7; } void main() { print('before'); receiver().insert(index(), element()); print('after'); }",
      "dynamic element() { print('element'); return 'wrong'; } void main() { List<Object> values = const <int>[1]; print('before'); values.insert(-1, element()); print('after'); }",
      "void main() { var values = List<int>.filled(1, 1); print('before'); values.insert(-1, 7); print('after'); }",
      "void main() { print('before'); const <int>[].insert(0, 7); print('after'); }",
      "List<int> receiver() { print('receiver'); return <int>[]; } dynamic index() { print('index'); return 'wrong'; } int element() { print('element'); return 7; } void main() { print('before'); receiver().insert(index(), element()); print('after'); }",
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
      final expected = await capture(sdk, [source.path]);
      await run(
        driver,
        compileArguments(source, executable),
        native: compiler != null,
      );
      final actual = await capture(
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
      'generic-aliases-library.dart': r'''
// @dart=3.7
library generic.aliases;
import 'dart:ffi';
part 'generic-aliases-part.dart';
typedef Rows<T extends num>=List<T?>;
typedef TypedList<T extends List<int>>=T;
typedef TypedNested<T extends List<List<int>>>=T;
typedef NativeShadow<Int64> = Int64 Function(Int64);
typedef PrivateList<T> = List<_Scalar>;
class Carrier {
  final int value;
  const Carrier([this.value=7]);
  const Carrier.named(this.value);
  static int twice(int value)=>value*2;
}
typedef ClassAlias<T extends num> = Carrier;
typedef Identity<T> = T;
typedef Concrete = Identity<Carrier>;
typedef Phantom<T> = Carrier;
typedef Annotated<@pragma('OtherTool:hint',const <Phantom<T>>[]) T> = List<T>;
''',
      'generic-aliases-part.dart': r'''
// @dart=3.7
part of 'generic-aliases-library.dart';
typedef _Scalar = int;
typedef Transform<T> = T Function(T);
typedef _ = int;
typedef WildcardLookup<_> = List<_>;
''',
      'generic-aliases-export.dart': "export 'generic-aliases-library.dart' show Rows,TypedList,TypedNested,NativeShadow,PrivateList,Transform,ClassAlias,Concrete,Carrier,Annotated,WildcardLookup;",
      'generic-aliases-old.dart': r'''
// @dart=2.12
typedef _ Transform<_>(_ value);
int next(int value)=>value+1;
int current(){Transform<int> callback=next;return callback(1);}
''',
      'generic-aliases-imports.dart': r'''
import 'generic-aliases-export.dart' as p;
import 'generic-aliases-old.dart' as old;
typedef _Scalar=String;
int step(int value)=>value+1;
void main(){
  p.Rows<int> values=[null,7];print(values);
  p.TypedList<List<int>> typed=[2];print(typed);
  p.TypedNested<List<List<int>>> nested=[[3]];print(nested);
  p.NativeShadow<int> nativeShadow=step;print(nativeShadow(8));
  p.PrivateList<bool> private=[1];print(private);
  p.Transform<int> callback=step;print(callback(7));
  print(new p.ClassAlias<int>(9).value);
  print(const p.ClassAlias<int>.named(10).value);
  print(p.ClassAlias.twice(3));
  print(<int>[p.Concrete.twice(2),const p.Concrete(11).value]);
  p.WildcardLookup<bool> ignored=[7];print(ignored);
  p.Annotated<int> annotated=[1];print(annotated);
  print(old.current());
}
''',
      'parts-dep.dart':
          'const int delta=7;class Value{int amount;Value(this.amount);}',
      'parts-main.dart': r'''
library parts.sample;
import 'parts-dep.dart' as dep;
part 'parts-uri.dart';
part 'parts-name.dart';
const mark='annotation';
const int _offset=3;
int _state=0;
int get split=>_state;
class Hidden{int _value=10;}
''',
      'parts-uri.dart': r'''
@mark
part of 'parts-main.dart';
int read(Hidden value){_state++;return value._value+dep.delta;}
int localPart(){int inside(dep.Value value)=>value.amount+_offset;return inside(dep.Value(4));}
set split(int value){_state=value;}
''',
      'parts-name.dart': r'''
part of parts.sample;
int named()=>_state;
class PartBox{int _value=5;}
int part()=>2;
void main(){
  print(read(Hidden()));print(named());
  split=4;print(split);print(PartBox()._value);print(part());print(localPart());
}
''',
      'parts-forbidden.dart': "part of parts.sample;import 'parts-dep.dart';",
      'parts-version.dart': "// @dart=3.12\npart of parts.sample;",
      'parts-shared.dart': 'part of parts.shared;int shared=1;',
      'parts-other.dart': "library parts.shared;part 'parts-shared.dart';",
      'conditional-first.dart': 'const int chosen=21;',
      'conditional-other.dart': 'const int chosen=99;',
      'conditional-export.dart': r'''
export 'conditional-missing-default.dart'
    if (dart . library . core == 'tr' 'ue') 'conditional-first.dart'
    if (dart.library.ffi) 'conditional-missing-later.dart' show chosen;
''',
      'conditional-fallback.dart': r'''
import 'conditional-first.dart'
    if (dart.library.nonexistent == '') 'conditional-missing-empty.dart'
    if (dart.library.nonexistent == 'false') 'conditional-missing-false.dart'
    if (dart.library.Function) 'conditional-missing-Function.dart' as value;
int fallback()=>value.chosen;
''',
      'conditional-imports.dart': r'''
import 'conditional-missing-default.dart'
    if (dart.library.ffi) 'conditional-first.dart'
    if (dart.library.core) 'conditional-missing-later.dart' as direct show chosen;
import 'conditional-export.dart' as exported;
import 'conditional-fallback.dart';
void main(){print(direct.chosen);print(exported.chosen);print(fallback());}
''',
      'conditional-io.dart': "import 'dart:io';",
      'function-first.dart': r'''
// @dart=2.12
typedef Unary=int Function(int);
int value(int input)=>input+40;
const saved=value;
const nested=<List<Unary>>[<Unary>[value]];
class Receiver {
  int value;
  Receiver(this.value);
  int add(int next)=>value+=next;
  int call(int next)=>add(next);
  int _read()=>value;
  int Function() privateCallback()=>_read;
}
final receiver=Receiver(5);
''',
      'function-other.dart':
          'int value(int input)=>input+40; const saved=value;',
      'function-exports.dart': "export 'function-first.dart' show Unary,value,saved,nested,Receiver,receiver;",
      'function-imports.dart': r'''
import 'function-first.dart' as first;
import 'function-exports.dart' as alias;
import 'function-other.dart' as other;
void main(){
  print(identical(first.value,alias.saved));
  print(first.value==alias.value);
  print(identical(first.saved,other.saved));
  print(alias.nested[0][0](2));
  first.Unary callback=alias.value;
  print(callback.call(3));
  first.Unary method=alias.receiver.add;
  print(method==first.receiver.add);
  print(method(2));
  print(first.receiver.privateCallback()());
  first.Unary callable=alias.receiver;
  print(callable==first.receiver.call);
  print(callable(3));
  print(alias.receiver(4));
}
''',
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
class Callable { int call(int value) => value + 1; }
@noGc
int invoke(Callable value) => value(3);
void main() { print(compute(65)); print(box(true)); print(box(false)); print(safe('a', 'long')); print(invoke(Callable())); }
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
  final int _X;
  final int _required;
  Secret({this._value = 1, this._X = 2, this._required = 3});
  int read() => _value;
  int upper() => _X;
  int contextual() => _required;
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
  print(secret.Secret(X: 9).upper());
  print(secret.Secret(required: 10).contextual());
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
      'named-constructors-library.dart': r'''
library named.constructors;
part 'named-constructors-part.dart';
int named() => 99;
class NamedLibraryChoice {
  final int value;
  const NamedLibraryChoice.new(this.value);
  const NamedLibraryChoice.named([int value = 4]) : value = value;
  const NamedLibraryChoice.other({this.value = 4});
  const NamedLibraryChoice._hidden(int value) : this.new(value);
  const NamedLibraryChoice.forward([int value = 3]) : this._hidden(value);
  const NamedLibraryChoice.chain({int value = 3}) : this.forward(value);
}
class NamedScope {
  NamedScope.named();
  int read() => named();
}
typedef NamedLibraryAlias = NamedLibraryChoice;
typedef ChainedLibraryAlias = NamedLibraryAlias;
NamedLibraryChoice hiddenChoice() => partChoice;
''',
      'named-constructors-part.dart': r'''
part of 'named-constructors-library.dart';
const partChoice = NamedLibraryChoice._hidden(3);
''',
      'named-constructors-export.dart': "export 'named-constructors-library.dart' show NamedLibraryChoice, NamedLibraryAlias, ChainedLibraryAlias, NamedScope, hiddenChoice;",
      'named-constructors-imports.dart': r'''
import 'named-constructors-library.dart' as direct;
import 'named-constructors-export.dart' as p;
@p.ChainedLibraryAlias.chain(value: 5)
@p.NamedLibraryAlias.new(6)
void annotated() {}
int selected([p.NamedLibraryChoice value = const p.ChainedLibraryAlias.chain(value: 9)]) => value.value;
void main() {
  const first = p.NamedLibraryAlias.named();
  print(identical(first, const direct.NamedLibraryChoice.other()));
  print(identical(p.hiddenChoice(), const direct.NamedLibraryChoice(3)));
  print(p.NamedScope.named().read());
  print(selected());
  print(new p.ChainedLibraryAlias.named(10).value);
  print(identical(const p.NamedLibraryChoice.chain(), p.hiddenChoice()));
}
''',
      'static-members-library.dart': r'''
library static.members;
part 'static-members-part.dart';
class StaticLibrary {
  static int _count = 3;
  static const int seed = 7;
  static int get count => _count;
  static int add(int amount) { _count += amount; return _count; }
  static int _read() => _count;
  static int fromPart() => staticPartRead();
}
''',
      'static-members-part.dart': r'''
part of 'static-members-library.dart';
int staticPartRead() => StaticLibrary._read();
''',
      'static-members-export.dart':
          "export 'static-members-library.dart' show StaticLibrary;",
      'static-members-imports.dart': r'''
import 'static-members-library.dart' as direct;
import 'static-members-export.dart' as p;
@p.StaticLibrary.seed
void annotated() {}
int selected([int value = p.StaticLibrary.seed]) => value;
void main() {
  print(p.StaticLibrary.count);
  const callback = p.StaticLibrary.add;
  int Function(int) typed = callback;
  print(identical(typed, direct.StaticLibrary.add));
  print(typed(2));
  print(direct.StaticLibrary.count);
  print(p.StaticLibrary.fromPart());
  print(selected());
}
''',
      'const-class-first.dart': "class Item { final int value; const Item(this.value); } const item = Item(7);",
      'const-class-second.dart': "class Item { final int value; const Item(this.value); } const item = Item(7);",
      'const-class-exports.dart':
          "export 'const-class-first.dart' show Item, item;",
      'const-class-imports.dart': "import 'const-class-first.dart' as first; import 'const-class-exports.dart' as alias; import 'const-class-second.dart' as other; const value = first.Item(7); @alias.Item(7) void annotated() {} void main() { print(identical(value, alias.item)); print(identical(value, first.item)); print(identical(value, other.item)); print(value.value); }",
      'const-class-metadata-only.dart': "class UnusedTag { final int value; const UnusedTag(this.value); String toString() { print('unused metadata'); return 'tag'; } } const unused = UnusedTag(7); @unused void neverCalled() { print('never called'); } @UnusedTag(8) void main() { print(42); }",
      'const-class-finite-default.dart': "class C { final C? next; const C([this.next = const C(null)]); } void main() { const first = C(); const same = C(C(null)); print(identical(first, same)); print(first.next!.next); var one = C(); var two = C(); print(identical(one, two)); print(identical(one.next, two.next)); print(identical(one.next, first.next)); }",
      'redirect-finite-constant.dart': "class C { final C? child; const C(int depth) : this.value(depth == 0 ? null : const C(0)); const C.value(this.child); } void main() { const value = C(1); print(value.child == null); print(value.child!.child); print(identical(value, const C.value(C(0)))); }",
    };
    for (final entry in libraries.entries) {
      File('${temporary.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    await compare(File('${temporary.path}/imports.dart'), []);
    await compare(File('${temporary.path}/core.dart'), []);
    await compare(File('${temporary.path}/priority.dart'), []);
    await compare(File('${temporary.path}/export-priority.dart'), []);
    await compare(File('${temporary.path}/prefix-priority.dart'), []);
    await compare(File('${temporary.path}/core-annotations-imports.dart'), []);
    await compare(File('${temporary.path}/core-annotations-implicit.dart'), []);
    await compare(File('${temporary.path}/core-annotations-own.dart'), []);
    await compare(File('${temporary.path}/core-annotations-filtered.dart'), []);
    await compare(File('${temporary.path}/nogc-values.dart'), []);
    await compare(File('${temporary.path}/nogc-user-annotation.dart'), []);
    await compare(File('${temporary.path}/version-imports.dart'), []);
    await compare(File('${temporary.path}/version-header.dart'), []);
    await compare(File('${temporary.path}/version-named.dart'), []);
    await compare(File('${temporary.path}/version-unnamed.dart'), []);
    await compare(File('${temporary.path}/version-markers.dart'), []);
    await compare(File('${temporary.path}/version-bom.dart'), []);
    await compare(File('${temporary.path}/constant-imports.dart'), []);
    await compare(File('${temporary.path}/property-imports.dart'), []);
    await compare(File('${temporary.path}/top-accessor-imports.dart'), []);
    await compare(File('${temporary.path}/metadata-imports.dart'), []);
    await compare(
      File('${temporary.path}/named-constructors-imports.dart'),
      [],
    );
    await compare(File('${temporary.path}/const-class-imports.dart'), []);
    await compare(File('${temporary.path}/const-class-metadata-only.dart'), []);
    await compare(
      File('${temporary.path}/const-class-finite-default.dart'),
      [],
    );
    await compare(File('${temporary.path}/redirect-finite-constant.dart'), []);
    await compare(File('${temporary.path}/static-members-imports.dart'), []);
    await compare(File('${temporary.path}/generic-aliases-imports.dart'), []);
    await compare(File('${temporary.path}/function-imports.dart'), []);
    await compare(File('${temporary.path}/conditional-imports.dart'), []);
    await compare(File('${temporary.path}/parts-main.dart'), []);
    final rejectedTypeAliases = [
      'typedef int Invalid(int value=1);void main(){}',
      'typedef int Invalid(var value);void main(){}',
      'typedef int Invalid(int value,int value);void main(){}',
      'typedef T Invalid<T,T>(T value);void main(){}',
      'typedef int Invalid = int Function();void main(){}',
      'typedef Number<T extends num> = int;typedef Erase<T> = int;typedef Invalid<T> = Erase<Number<T>>;void main(){}',
      'class C{C();}typedef Identity<T> = T?;void main(){Identity<C>();}',
      'class C{static int value()=>1;}typedef A<T> = C;void main(){print(A<int>.value());}',
      'typedef Invalid<T extends T> = List<T>;void main(){}',
      'typedef Erase<T> = int;typedef A<T> = Erase<B<T>>;typedef B<T> = A<T>;void main(){}',
      'class C{}typedef A<T extends num> = C;typedef Invalid = A<dynamic>;void main(){}',
      'typedef Erase<T> = int;typedef A<T extends Erase<T>> = T;typedef B<T extends A> = T;void main(){B b=7;print(b);}',
      'typedef Invalid<T,T> = int;void main(){}',
      'typedef N<T extends num> = List<T>;typedef Invalid<T> = N<T>;void main(){}',
      'typedef N<T extends num> = List<T>;N<String>? value;void main(){}',
      'typedef Ignored<_,_> = int;Ignored<int> value=1;void main(){}',
      'const tag=1;typedef Invalid<@tag tag> = List<tag>;void main(){}',
      "typedef Invalid<@pragma('OtherTool:hint',const <T>[]) T> = List<T>;void main(){}",
      "import 'generic-aliases-export.dart' as p;typedef Invalid<p> = p.Carrier;void main(){}",
      '// @dart=2.12\ntypedef Invalid<T> = List<T>;void main(){}',
      '// @dart=3.6\ntypedef Invalid<_,_> = int;void main(){}',
      'typedef Invalid<get> = int;void main(){}',
    ];
    final rejected = [
      'class C{int call(int x)=>x;}void unused(){String Function(int) f=C();}void main(){}',
      'class C{int call(int x)=>x;}void unused(){int Function(Object?) f=C();}void main(){}',
      'class C{int call(int x)=>x;}void unused(C? c){int Function(int)? f=c;}void main(){}',
      'class C{int call()=>1;}void unused(C? c){c();}void main(){}',
      'class C{static int call()=>1;}void unused(){C()();}void main(){}',
      'class C{int Function() get call=>()=>1;}void unused(){C()();}void main(){}',
      'class C{int Function() call=()=>1;}void unused(){Function f=C();}void main(){}',
      'class C{int call()=>1;}void unused(){C()(1);}void main(){}',
      'class C{int call()=>1;}void unused(){C()<int>();}void main(){}',
      'class C{const C();int call()=>1;}const Function f=C();void main(){}',
      'class C{const C();int call()=>1;}const f=<String Function()>[if(false) C()];void main(){}',
      'class C{const C();int call()=>1;}const f=<Function>[C()];void main(){}',
      'class C{int call()=>1;}void unused(){print(<Function>[...<C>[C()]]);}void main(){}',
      'class C{int call()=>1;}void unused(C? c){print(<Function>[?c]);}void main(){}',
      'class C{int call()=>1;}class D{int call()=>1;}Function unused(bool b)=>b?C():D();void main(){}',
      'class C{int call()=>1;}class D{int call()=>1;}Function unused(C? c)=>c??D();void main(){}',
      "class C{int call()=>1;}@pragma('dartc:no-gc') int Function() extract(C value)=>value;void main(){}",
      'class C{int read(int x)=>x;}void unused(){String Function(int) f=C().read;print(f);}void main(){}',
      'class C{int read(int x)=>x;}void unused(){int Function(Object?) f=C().read;print(f);}void main(){}',
      'class C{int read()=>1;}C? maybe()=>null;void unused(){var f=maybe().read;print(f);}void main(){}',
      'class C{int read()=>1;}void main(){print(C.read);}',
      'class C{int read()=>1;}void main(){C().read=()=>2;}',
      'class C{const C();int read()=>1;}const c=C();const f=c.read;void main(){}',
      'class C{const C();int read()=>1;}const c=C();const f=[if(false) c.read];void main(){}',
      "import 'function-first.dart';void main(){print(receiver._read);}",
      'class C{int Function() value;C():value=read;int read()=>1;}void main(){}',
      '// @dart=3.7\nvoid unused(){print([?null]);}void main(){}',
      '// @dart=3.7\nconst values=[?null];void main(){}',
      'String? absent()=>null;void unused(){print(<int>[?absent()]);}void main(){}',
      'void unused(){print([if(false) ?missing]);}void main(){}',
      'void f(){}void unused(){print(<int>[?f()]);}void main(){}',
      'void main(){print([??null]);}',
      'void main(){print([?if(true) 1]);}',
      'const dynamic x="bad";const values=<int>[?x];void main(){}',
      'const Object? x=null;const values=<int>[?x];void main(){}',
      'int? f()=>null;const values=[if(false) ?f()];void main(){}',
      'int? f()=>null;void main(){var x=f();print([?x,x+1]);}',
      "void unused(){print(<int>[if(false) 'wrong']);}void main(){}",
      "void unused(){print([if(1) 2]);}void main(){}",
      "void unused(){print([for(var i in [1]) if(false) missing]);}void main(){}",
      "void main(){var values=[for(var i in [1]) i];print(i);print(values);}",
      "void main(){final int i;print([for(i in [1,2]) i]);}",
      "void main(){final i=0;print([for(i in [1]) i]);}",
      "List<String>? f()=>null;void main(){print(<int>[...?f()]);}",
      "List<int>? f()=>null;void main(){print([...f()]);}",
      "void main(){print([...1]);}",
      "void f(){}void main(){print([...f()]);}",
      "const list=[if(false) ...<int>[1][0]];void main(){}",
      "const list=[if(false) for(var i=0;i<1;i++) i];void main(){}",
      "int f()=>1;const list=[if(false) f()];void main(){}",
      "const list=<int>[if(false) 'wrong'];void main(){}",
      "const dynamic values=<Object>[1,'wrong'];const list=<int>[...values];void main(){}",
      "void main(){List<int>? a=null;print([... ? a]);}",
      "void main(){final int value;print([if(false) value=1]);print(value);}",
      'class C{int value=1;}void main(){int value=C()?.value;print(value);}',
      'class C{int value=1;}C? maybe()=>C();void main(){(maybe()?.value)=2;}',
      'class C{int value=1;}C? maybe()=>null;void main(){print(-maybe()?.value);}',
      'class C{void run(){}}void unused(){print(C()?.run());}void main(){}',
      'class C{int Function(int) get callback=>(x)=>x;}C? maybe()=>null;void main(){print((maybe()?.callback)(1));}',
      'class C{int value=1;C child()=>C();}C? maybe()=>null;void main(){maybe()?.child()..value=3;}',
      'class C{int value=1;}C? maybe()=>null;void main(){int x;maybe()?.value=x=1;print(x);}',
      'class C{int value=1;}C? maybe()=>null;void main(){final int x;maybe()?.value=x=1;x=2;}',
      'class C{int value=1;}C? maybe()=>null;void unused(){maybe()?.value="wrong";}void main(){}',
      'const x=true ? 2 : <int>[1][true];void main(){}',
      'const value=null?.missing();void main(){}',
      'int f()=>1;const value=null?[f()];void main(){}',
      'const value=null?.missing=1;void main(){}',
      'const String? value=null;const result=value?.missing;void main(){}',
      'const value=<int>[1]?.length;void main(){}',
      'void main(){List<int>? x=null;print(true ? x?[0] : 0);}',
      "import 'dart:core' as p;void main(){p?.print(1);}",
      '// @dart=3.8\nclass C{int value=0;}void main(){final int x;C()?.value=x=1;print(x);}',
      '// @dart=3.8\nclass C{int value=0;}void main(){final int x;C()?..value=x=1;print(x);}',
      "class C{int value=0;}C? maybe()=>null;void unused(){maybe()?..value='wrong';}void main(){}",
      'class C{final int value=0;}void main(){C()..value=1;}',
      'const values=<int>[]..add(1);void main(){}',
      'class C{int value=0;}void main(){C()?..value=1?..value=2;}',
      'class C{int value=0;}C? maybe()=>null;void main(){int x;maybe()?..value=x=1;print(x);}',
      'class C{int value=0;}C? maybe()=>null;void main(){final int x;maybe()?..value=x=1;x=2;print(x);}',
      'class C{int value=0;}C? maybe()=>null;void main(){C x=maybe()?..value=1;print(x);}',
      'class C{int value=0;}C? maybe()=>null;void main(){var x=maybe();x?..value=1;print(x.value);}',
      'void main(){print(null?..missing=print(1));}',
      'void main(){print(1)..toString();}',
      'class C{int value=0;}void main(){C()..value++;}',
      'class C{void call(){}}void main(){C()..call()=1;}',
      "void main(){int? value=3;void clear(){value=null;}value!;clear();print(value+1);}",
      "void main(){int? value;void clear(){value=null;}value??=3;clear();print(value+1);}",
      "void main(){final int value;void initialize(){value=7;}initialize();}",
      "void main(){int value;int read()=>value;value=7;print(read());}",
      "void main(){int value;void initialize(){value=7;}initialize();print(value);}",
      "void main(){Object value='bad';value=7;if(value is int){int read()=>value+1;print(read());}}",
      "void main(){Object value=7;if(value is int){int read()=>value+1;value='bad';print(read());}}",
      "void main(){Object value=7;void change(){value='bad';}if(value is int){change();print(value+1);}}",
      "class C{int value=1;final int Function() read;C():read=(()=>value);}void main(){print(C().read());}",
      "class C{int value=1;final int Function() read;C():read=(()=>this.value);}void main(){print(C().read());}",
      'class C{C.named();}typedef A=C?;void main(){List<C> values=[A.named()];print(values);}',
      "import 'named-constructors-export.dart' as p;typedef LocalAlias=p.NamedLibraryChoice;void main(){LocalAlias._hidden(3);}",
      "import 'named-constructors-export.dart' as p;typedef LocalAlias=p.NamedLibraryChoice;const value=LocalAlias._hidden(3);void main(){}",
      '// @dart=2.14\nclass C{C();}typedef A=C;void main(){A.new();}',
      "class C{static String toString()=>'';}void main(){}",
      'class C{static int hashCode=0;}void main(){}',
      'class C{C.named();static int named()=>1;}void main(){}',
      'class C{static int value=1;int value=2;}void main(){}',
      'class C{static int get value=>1;set value(int next){}}void main(){}',
      'class C{static int value=1;static set value(int next){}}void main(){}',
      'class C{static int method()=>1;static int get method=>2;}void main(){}',
      'int value=9;class C{int value=1;static int read()=>value;}void main(){}',
      'class C{static int read()=>this.hashCode;}void main(){}',
      'class C{static int value=1;}void main(){print(C().value);}',
      'class C{static int value;}void main(){}',
      'class C{static final int? value;}void main(){}',
      'int ordinary()=>1;class C{static const int value=ordinary();}void main(){}',
      'class C{static int value="wrong";}void main(){}',
      'class C{static final int value=1;}void main(){C.value=2;}',
      'class C{static int value=1;C(this.value);}void main(){}',
      "import 'static-members-export.dart' as p;void main(){print(p.StaticLibrary._count);}",
      "import 'static-members-export.dart' as p;void main(){print(p.StaticLibrary._read());}",
      'class C{C():this();}void main(){}',
      'class C{C.first():this.second();C.second():this.first();}void main(){}',
      'class C{int value;C.base(this.value);C.bad(this.value):this.base(value);}void main(){}',
      'class C{int value;C.base(this.value);C.bad():value=1,this.base(2);}void main(){}',
      'class C{C.base();C.bad():this.base(){}}void main(){}',
      'class C{C():this.missing();}void main(){}',
      'class C{C.base(int value);C():this.base("wrong");}void main(){}',
      'class C{final int value;C.base(this.value);const C(int value):this.base(value);}void main(){}',
      'int ordinary(int value)=>value;class C{final int value;const C.base(this.value);const C(int input):this.base(ordinary(input));}void main(){}',
      'class C{final int value;const C.base(this.value);const C(int input):this.base(input=2);}void main(){}',
      'class C{final List<int> values;const C.base(this.values);const C(int input):this.base([input]);}void main(){}',
      'class C{final List<int> values;const C.base(this.values);const C(int input):this.base(const[input]);}const value=C(7);void main(){}',
      "class C{final int value;const C.base(this.value);const C(int value):this.base(value);}const Object value=true?0:const C('wrong');void main(){print(value);}",
      'class C{final C? child;const C():this.value(const C());const C.value(this.child);}void main(){const value=C();print(value);}',
      '// @dart=2.12\nvoid main(){(List<int>.filled)(1,3);}',
      '// @dart=2.12\nvoid main(){(String.fromCharCodes)(<int>[65]);}',
      "void main(){new int.parse('7');}",
      "import 'dart:ffi';typedef Callback=Int64 Function(Int64);int target(int value)=>value;void main(){new Pointer.fromFunction<Callback>(target,0);}",
      'int value()=>1;void main(){new value();}',
      'int target()=>1;int Function() get value=>target;void main(){new value();}',
      'void main(){int value()=>1;new value();}',
      'int target()=>1;void main(){var value=target;new value();}',
      'class C{const C();}const value=new C();void main(){}',
      'class C{const C();}const values=<C>[new C()];void main(){}',
      'class C{const C();}const value=true?null:new C();void main(){}',
      'class Child{const Child();}class C{final Child child;const C():child=new Child();}void main(){}',
      // Constructor tear-offs are valid Dart but are not yet supported.
      'class C{C.named();}void main(){(C.named)();}',
      '// @dart=2.12\nclass C{C.named();}void main(){(C.named)();}',
      'class C{const C.named();}const value=(C.named)();void main(){}',
      'class C{C.named();C.named();}void main(){}',
      'class C{C();C.new();}void main(){}',
      'class C{C.named();}void main(){C();}',
      'class C{C.named();}void main(){C.other();}',
      "import 'named-constructors-export.dart' as p;void main(){p.NamedLibraryChoice._hidden(3);}",
      "import 'named-constructors-export.dart' as p;const value=p.NamedLibraryChoice._hidden(3);void main(){}",
      '// @dart=2.14\nclass C{C.new();}void main(){C();}',
      '// @dart=2.14\nclass C{C();}void main(){C.new();}',
      'void main(){var callback=<T>(T value)=>value;print(callback<int>(1));}',
      'void main(){var callback=()async=>1;callback();}',
      'void main(){const callback=()=>1;print(callback());}',
      'void main(){int Function(int) callback=(value)=>"wrong";print(callback(1));}',
      'void main(){void Function() callback=(){return 1;};callback();}',
      'int value()=>99;void main(){print(value());int value()=>7;}',
      'void main(){int first(int value)=>second(value);int second(int value)=>first(value);}',
      'void main(){int value()=>1;int value()=>2;}',
      'int other()=>2;void main(){int value()=>1;value=other;}',
      'void main(){int value()=>1;const saved=value;print(saved());}',
      'void main(){int value();}',
      "void main(){int String()=>1;String value='wrong';print(value);}",
      "void main(){int String=1;String value='wrong';print(value);}",
      "import 'properties.dart' as p;void main(){int p=1;p.Counter? value;print(value);}",
      'void main(){int value()=>bias;const bias=7;print(value());}',
      'void touch(){}void main(){value(bool flag){if(flag)return touch();return 1;}}',
      'void main(){outer:while(true){value(){break outer;}break;}}',
      // NoGC contracts also apply to unused local bodies (valid ordinary Dart).
      "void main(){@pragma('dartc:no-gc') List<int> value()=>[1];}",
      "import 'conditional-first.dart' if(true) 'conditional-other.dart';void main(){}",
      "import 'conditional-first.dart' if(dart.library.if) 'conditional-other.dart';void main(){}",
      "import 'conditional-first.dart' if(dart.library.core && true) 'conditional-other.dart';void main(){}",
      "import 'conditional-first.dart' if(dart.library.core == true) 'conditional-other.dart';void main(){}",
      r"import 'conditional-first.dart' if(dart.library.nonexistent) 'x${1}.dart';void main(){}",
      r"import 'conditional-first.dart' if(dart.library.core == '${true}') 'conditional-other.dart';void main(){}",
      'int value(int input)=>input; void main(){int Function(Object?) callback=value;print(callback(null));}',
      'int value(int input)=>input; void main(){int Function(int) callback=value;callback();}',
      'void main(){int Function(int)? callback;callback(1);}',
      'typedef First=Later;typedef Later=First Function(int);void main(){}',
      'void value(){} @value void main(){}',
      "@pragma('dartc:no-gc') void invoke(void Function() callback)=>callback();void target(){print(1);}void main(){invoke(target);}",
      "class C{int read()=>1;}@pragma('dartc:no-gc') int Function() extract(C value)=>value.read;void main(){}",
      '// @dart=2.12\ntypedef F=int Function();typedef Copy=F;void main(){}',
      '// @dart=2.12\ntypedef Nullable=int Function()?;void main(){}',
      'typedef Function=int;void main(){Function value=7;print(value);}',
      "@pragma('dartc:no-gc') int checked(String value,int index)=>value.codeUnitAt(index);void main(){print(checked('a',0));}",
      "@pragma('dartc:no-gc') int checked(String value)=>int.parse(value);void main(){print(checked('7'));}",
      "@pragma('dartc:no-gc') void checked(List<int> values){values.clear();}void main(){var values=<int>[1];checked(values);print(values.length);}",
      "@pragma('dartc:no-gc') int checked(List<int> values,int index)=>values.removeAt(index);void main(){}",
      "void main(){@pragma('dartc:no-gc') int checked(List<int> values,int index)=>values.removeAt(index);}",
      "@pragma('dartc:no-gc') void checked(List<int> values,int index,int element){values.insert(index,element);}void main(){}",
      "void main(){<int>[].insert(0);}",
      "void main(){<int>[].insert('wrong',1);}",
      "void main(){<int>[].insert(0,'wrong');}",
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
      'class C { int? value; C(this.value):value=2; } void main() {}',
      'class C { int? value; C():value=1,value=2; } void main() {}',
      'class C { final int value=1; C():value=2; } void main() {}',
      'class C { final int value; int other; C():other=1; } void main() {}',
      'class C { int get value=>1; C():value=2; } void main() {}',
      'class C { int value=1; final int other; C():other=value; } void main() {}',
      'class C { int value=1; final int other; C():other=this.value; } void main() {}',
      'class C { int value; final int other; C(this.value):other=(value=2); } void main() {}',
      'class C { int _value; final int other; C({this._value=1}):other=value; } void main() {}',
      'class C { final int value; C():value="wrong"; } void main() {}',
      'int ordinary(int value)=>value; class C { final int value; const C(int input):value=ordinary(input); } void main() {}',
      'class C { final int value; const C(int input):value=(input=2); } void main() {}',
      'class C { final List<int> values; const C(int input):values=[input]; } void main() {}',
      'class C { final List<int> values; const C(int input):values=const[input]; } void main() {}',
      // These initializer forms are valid Dart but remain unsupported.
      'class C { C():assert(true); } void main() { C(); }',
      'class C { C():super(); } void main() { C(); }',
      'void main() { final int? value; print(value); }',
      'void f(bool flag) { final int value; if (flag) value = 1; value = 2; print(value); } void main() { f(false); }',
      'void main() { final int value; for (int i = 0; i < 2; i++) { value = i; } }',
      'void main() { final int value; do { value = 1; } while (false); print(value); }',
      'int value() {} void main() { print(value()); }',
      'int value(bool flag) { if (flag) return 1; } void main() { print(value(false)); }',
      'int value = 2; const selected = 1 ?? value; void main() { print(selected); }',
      "void main() { var values = [1 ?? 'other']; List<int> narrow = values; print(narrow); }",
      'void main() { print(9223372036854775808); }',
      'const value = 9223372036854775808; void main() { print(value); }',
      'void main() { print(-9223372036854775809); }',
      'void main() { print(-(9223372036854775808)); }',
      'const value = -(9223372036854775808); void main() { print(value); }',
      'const value = 0x10000000000000000; void main() { print(value); }',
      'void main() { print(-0xffffffffffffffff); }',
      'const value = -0xffffffffffffffff; void main() { print(value); }',
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
      'class C { int _x; C({int x = 2, this._x = 1}); } void main() {}',
      'class C { int _2x; C({this._2x = 1}); } void main() {}',
      'class C { int _class; C({this._class = 1}); } void main() {}',
      'class C { int _x; C(int x, {this._x = 1}); } void main() {}',
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
    Future<void> reject(
      File invalid, {
      String? runtime,
      String? diagnostic,
      int status = 1,
      List<String> options = const [],
      String? workingDirectory,
      bool checkSdk = false,
    }) async {
      if (checkSdk) {
        final expected = await capture(sdk, [
          'compile',
          'kernel',
          ...sdkOptions(options),
          invalid.path,
          '-o',
          '${invalid.path}.dill',
        ], workingDirectory: workingDirectory);
        if (expected.exitCode == null ||
            expected.exitCode == 0 ||
            expected.timedOut ||
            expected.outputLimited ||
            expected.startError != null ||
            expected.captureError != null)
          throw StateError('Expected SDK rejection for ${invalid.path}.');
      }
      final result = await capture(
        driver,
        [
          ...compileArguments(invalid, '${invalid.path}.out', runtime),
          ...options,
        ],
        workingDirectory: workingDirectory,
        environment: compiler == null ? null : {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: compiler == null,
      );
      if (result.exitCode != status ||
          !'${result.stdout}${result.stderr}'.contains(
            diagnostic ?? invalid.path,
          )) {
        throw StateError(
          'Expected source diagnostic for ${invalid.path}: '
          '${result.stdout}${result.stderr}',
        );
      }
    }

    for (var i = 0; i < rejectedTypeAliases.length; i++) {
      final invalid = File('${temporary.path}/rejected-type-alias-$i.dart')
        ..writeAsStringSync(rejectedTypeAliases[i]);
      await reject(invalid, checkSdk: true);
    }
    for (var i = 0; i < rejected.length; i++) {
      final invalid = File('${temporary.path}/rejected-$i.dart')
        ..writeAsStringSync(rejected[i]);
      await reject(invalid);
    }
    final rejectedParts = <String, String>{
      "import 'parts-name.dart';void main(){}": 'parts-name.dart',
      "library parts.sample;part 'parts-dep.dart';void main(){}":
          'parts-dep.dart',
      "library parts.sample;part 'parts-uri.dart';void main(){}":
          'parts-uri.dart',
      "library wrong;part 'parts-name.dart';void main(){}": 'parts-name.dart',
      "library parts.shared;part 'parts-shared.dart';part './parts-shared.dart';void main(){}":
          'parts-shared.dart',
      "library parts.sample;part 'parts-forbidden.dart';void main(){}":
          'parts-forbidden.dart',
      "library parts.shared;import 'parts-other.dart';part 'parts-shared.dart';void main(){}":
          'parts-shared.dart',
      "// @dart=3.13\nlibrary parts.sample;part 'parts-version.dart';void main(){}":
          'parts-version.dart',
      "// @dart=3.13\nlibrary parts.sample;part 'parts-name.dart';void main(){}":
          'parts-name.dart',
    };
    var partRejection = 0;
    for (var entry in rejectedParts.entries) {
      final invalid = File(
        '${temporary.path}/rejected-part-${partRejection++}.dart',
      )..writeAsStringSync(entry.key);
      await reject(invalid, diagnostic: '${temporary.path}/${entry.value}');
    }
    final conditionalIo = File('${temporary.path}/conditional-target-io.dart')
      ..writeAsStringSync(
        "import 'conditional-io.dart' if(dart.library.io) 'conditional-first.dart';void main(){}",
      );
    await run(sdk, [conditionalIo.path]);
    await reject(conditionalIo, diagnostic: 'unsupported library URI dart:io');
    for (final literal in ['1_', '0x_FF', '0_xFF']) {
      final invalid = File('${temporary.path}/separator-$literal.dart')
        ..writeAsStringSync('void main() { print($literal); }');
      final expected = await capture(sdk, [invalid.path]);
      if (expected.exitCode == 0) {
        throw StateError('Expected SDK rejection for ${invalid.path}.');
      }
      await reject(invalid, diagnostic: 'digit separator');
    }
    final packageProject = Directory(
      '${temporary.path}/packages-你好 space/project',
    );
    final packageCwd = Directory('${packageProject.parent.path}/unrelated')
      ..createSync(recursive: true);
    final packageState = File('${packageProject.path}/lib %/state.dart');
    packageState.parent.createSync(recursive: true);
    packageState.writeAsStringSync(
      'class Item { final int value; const Item(this.value); } '
      'const item=Item(7); int count=0; int tick()=>++count;',
    );
    final packageSubstate = File('${packageState.parent.path}/sub/state.dart');
    packageSubstate.parent.createSync(recursive: true);
    packageSubstate.writeAsStringSync('int count=0; int tick()=>++count;');
    final packageColon = File('${packageState.parent.path}/a:b.dart')
      ..writeAsStringSync('int count=0; int tick()=>++count;');
    File('${packageState.parent.path}/root.dart')
        .writeAsStringSync('const int value=41;');
    File('${packageProject.path}/root.dart')
        .writeAsStringSync('const int value=99;');
    File('${packageSubstate.parent.path}/middle.dart').writeAsStringSync(
      "import '../../root.dart' as clamped; "
      "import '${File('${packageProject.path}/root.dart').uri}' as absolute; "
      'int read()=>clamped.value+absolute.value;',
    );
    final packageMain = File('${packageProject.path}/bin/main.dart');
    packageMain.parent.createSync(recursive: true);
    packageMain.writeAsStringSync(
      "import 'package:probe/state.dart' as package; "
      "import '../lib%20%25/state.dart' as relative; "
      "import '${packageState.uri}' as absolute; "
      "import 'package:probe/sub//state.dart' as packageDouble; "
      "import 'package:probe/sub/state.dart' as packageSingle; "
      "import '${packageSubstate.parent.uri}/state.dart' as fileDouble; "
      "import '${packageSubstate.uri}' as fileSingle; "
      "import 'package:probe/a:b.dart' as packageColon; "
      "import 'package:probe/a%3Ab.dart' as packageEncoded; "
      "import '${packageColon.uri}' as fileColon; "
      "import '${packageColon.uri.toString().replaceFirst('/a:b.dart', '/a%3Ab.dart')}' as fileEncoded; "
      "import 'package:probe/sub/middle.dart' as clamped; "
      'int _=7; void main(){int _=2;print(_);'
      'print(identical(package.item,relative.item));'
      'print(identical(package.item,absolute.item));'
      'print(identical(relative.item,absolute.item));'
      'print(package.tick());print(relative.tick());print(absolute.tick());'
      'print(identical(packageDouble.tick,packageSingle.tick));'
      'print(packageDouble.tick());print(packageSingle.tick());'
      'print(identical(fileDouble.tick,fileSingle.tick));'
      'print(fileDouble.tick());print(fileSingle.tick());'
      'print(identical(packageColon.tick,packageEncoded.tick));'
      'print(packageColon.tick());print(packageEncoded.tick());'
      'print(identical(fileColon.tick,fileEncoded.tick));'
      'print(fileColon.tick());print(fileEncoded.tick());print(clamped.read());}',
    );
    final packageTest = File('${packageProject.path}/test/main.dart');
    packageTest.parent.createSync(recursive: true);
    packageTest.writeAsStringSync('int _=7; void main(){int _=2;print(_);}');
    final packageHeader = File('${packageProject.path}/test/header.dart')
      ..writeAsStringSync(
        '// @dart=3.13\nint _=7; void main(){int _=2;print(_);}',
      );
    final packageConfig = File(
      '${packageProject.path}/.dart_tool/package_config.json',
    );
    packageConfig.parent.createSync(recursive: true);
    final packageEntry = {
      'name': 'probe',
      'rootUri': '../',
      'packageUri': 'lib%20%25/',
      'languageVersion': '3.6',
    };
    packageConfig.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          packageEntry,
          {
            'name': 'runtime-input',
            'rootUri': File(standard).parent.uri.toString(),
            'languageVersion': '2.12',
          },
        ],
      }),
    );
    final unrelatedConfig = File(
      '${packageCwd.path}/.dart_tool/package_config.json',
    );
    unrelatedConfig.parent.createSync(recursive: true);
    unrelatedConfig.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            ...packageEntry,
            'rootUri': '../../project/',
            'languageVersion': '3.7',
          },
        ],
      }),
    );
    await compare(packageMain, [], workingDirectory: packageCwd.path);
    await compare(packageTest, [], workingDirectory: packageCwd.path);
    await compare(packageHeader, [], workingDirectory: packageCwd.path);
    await compare(
      packageMain,
      [],
      workingDirectory: packageCwd.path,
      options: ['--packages', packageConfig.path],
    );
    final nearestConfig = File(
      '${packageMain.parent.path}/.dart_tool/package_config.json',
    );
    nearestConfig.parent.createSync(recursive: true);
    nearestConfig.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {...packageEntry, 'rootUri': '../../', 'languageVersion': '3.7'},
        ],
      }),
    );
    await compare(packageMain, [], workingDirectory: packageCwd.path);
    await compare(
      packageMain,
      [],
      workingDirectory: packageCwd.path,
      options: ['--packages=${packageConfig.uri}'],
    );
    final uriBaseConfig = File('${packageConfig.parent.path}/uri-base.json')
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {...packageEntry, 'rootUri': '../../'},
          ],
        }),
      );
    await compare(
      packageMain,
      [],
      workingDirectory: packageCwd.path,
      options: [
        '--packages=${uriBaseConfig.parent.uri}/${uriBaseConfig.uri.pathSegments.last}',
      ],
    );
    final lastWinsConfig = File('${packageConfig.parent.path}/last-wins.json')
      ..writeAsStringSync(
        '\uFEFF' +
            r'''
{"configVersion":false,"config\u0056ersion":2,"packages":{},"packages":[
 {"name":0,"name":"probe","rootUri":false,"rootUri":"../",
  "packageUri":null,"packageUri":"lib%20%25/","languageVersion":[],"languageVersion":"3.6"}
],"unknown":{"values":[true,false,null,-1.25e+3,{"escape":"\u4F60\u597D\uD83D\uDE42"}]}}
''',
      );
    await compare(
      packageMain,
      [],
      workingDirectory: packageCwd.path,
      options: ['--packages', lastWinsConfig.path],
    );
    final nestedMain = File('${packageProject.path}/inner/bin/main.dart');
    nestedMain.parent.createSync(recursive: true);
    nestedMain.writeAsStringSync('int _=7; void main(){int _=2;print(_);}');
    packageConfig.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          packageEntry,
          {
            'name': 'inner',
            'rootUri': '../inner/',
            'packageUri': 'lib/',
            'languageVersion': '3.7',
          },
          {
            'name': 'future',
            'rootUri': '../unused/',
            'languageVersion': '3.14',
          },
        ],
      }),
    );
    await compare(
      packageMain,
      [],
      workingDirectory: packageCwd.path,
      options: ['--packages', packageConfig.path],
    );
    await compare(nestedMain, [], workingDirectory: packageCwd.path);
    nearestConfig.writeAsStringSync(
      '{"configVersion":2,"packages":[],"unknown":[1,]}',
    );
    await reject(
      packageMain,
      diagnostic: nearestConfig.path,
      checkSdk: true,
      workingDirectory: packageCwd.path,
    );
    final missingConfig = '${packageConfig.parent.path}/missing.json';
    await reject(
      packageMain,
      diagnostic: missingConfig,
      status: 64,
      checkSdk: true,
      workingDirectory: packageCwd.path,
      options: ['--packages', missingConfig],
    );
    final invalidConfigs = {
      'future-used': jsonEncode({
        'configVersion': 2,
        'packages': [
          {...packageEntry, 'languageVersion': '3.14'},
        ],
      }),
      'duplicate-roots': jsonEncode({
        'configVersion': 2,
        'packages': [
          packageEntry,
          {...packageEntry, 'name': 'other'},
        ],
      }),
      'overlap': jsonEncode({
        'configVersion': 2,
        'packages': [
          packageEntry,
          {'name': 'nested', 'rootUri': '../lib%20%25/nested/'},
        ],
      }),
      'outside': jsonEncode({
        'configVersion': 2,
        'packages': [
          {...packageEntry, 'packageUri': '../'},
        ],
      }),
      'version-number': '{"configVersion":2.0,"packages":[]}',
    };
    for (final entry in invalidConfigs.entries) {
      final config = File('${packageConfig.parent.path}/${entry.key}.json')
        ..writeAsStringSync(entry.value);
      await reject(
        packageHeader,
        // SDK 3.13.5 accepts this unused overlap; the pinned v2 format rejects it.
        checkSdk: entry.key != 'overlap',
        workingDirectory: packageCwd.path,
        diagnostic: entry.key == 'future-used'
            ? packageHeader.path
            : config.path,
        options: ['--packages=${config.path}'],
      );
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
    await run(
      driver,
      compileArguments(empty, emptyExecutable, emptyRuntime.path),
      native: compiler != null,
    );
    if ((await run(emptyExecutable, [], native: true)).stdout != '') {
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
    await run(
      driver,
      compileArguments(eager, eagerExecutable, eagerRuntime.path),
      native: compiler != null,
    );
    if ((await run(eagerExecutable, [], native: true)).stdout != '') {
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
      await reject(empty, runtime: runtime.path, diagnostic: runtime.path);
    }
    final runtimePart = File('${temporary.path}/runtime-part-body.dart')
      ..writeAsStringSync(
        "part of 'runtime-part-root.dart';external int nativeTarget();",
      );
    final partRuntime = File('${temporary.path}/runtime-part-root.dart')
      ..writeAsStringSync(
        "part 'runtime-part-body.dart';const int rtAbiVersion=$runtimeAbiVersion;",
      );
    await reject(
      empty,
      runtime: partRuntime.path,
      diagnostic: runtimePart.path,
    );
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
    await compare(
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
      final expected = await capture(sdk, [
        io.path,
        outputPrefix,
        'cwd',
      ], workingDirectory: directory.path);
      final actual = await capture(
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
    final directoryRead = await capture(
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
      await reject(invalid);
    }
    stdout.writeln('Behavior matches official Dart.');
    succeeded = true;
  } catch (error, stack) {
    exitCode = 1;
    final report = File('${temporary.path}/failure.json');
    try {
      report.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'error': error.toString(),
          'stack': stack.toString(),
          'arguments': args,
          'identities': identities,
          'processes': [for (final process in processes) process.toJson()],
        }),
      );
    } catch (recordError) {
      stderr.writeln('Could not write failure record: $recordError');
    }
    stderr.writeln('Behavior failure preserved at ${temporary.path}');
    stderr.writeln('Process evidence: ${report.path}');
    stderr.writeln(error);
  } finally {
    if (succeeded) temporary.deleteSync(recursive: true);
  }
}
