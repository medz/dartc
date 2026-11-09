import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('dartc-extensions-');
  });
  tearDown(() => directory.deleteSync(recursive: true));
  String source(String name, String text) {
    final file = File('${directory.path}/$name.dart')..writeAsStringSync(text);
    return file.path;
  }

  test(
    'prefixed imports, private selection, parts and ordinary precedence',
    () async {
      final entry = source('entry', '''
import 'other.dart' as other;
part 'one.dart';
part 'two.dart';
class Real { int m() => 30; }
extension Override on Real { int m() => 40; }
extension Private on int { int _private() => this + 1; }
int run() => other.Public(2).m() + other.Public.n + 3.mark() +
    'ab'.mark() + 1._private() + Real().m() + Override(Real()).m();
''');
      final other = source('other', '''
extension Public on int {
  int m() => this + 10;
  static int n = 20;
}
''');
      source(
        'one',
        "part of 'entry.dart'; extension on int { int mark() => this; }",
      );
      source(
        'two',
        "part of 'entry.dart'; extension on String { int mark() => 2; }",
      );
      final program = await AnalysisSession([entry, other])
          .use((input) => Lowering().lower(input).program);
      final run = program.functions.singleWhere((f) => f.target.name == 'run');
      expect(IrInterpreter(program, {}).run(run, []), 109);
      final markTargets = program.functions.where(
        (f) => f.target.name.endsWith(':method:mark>'),
      );
      expect(markTargets.length, 2);
      expect(markTargets.map((f) => f.target.name).toSet().length, 2);
    },
  );

  test('extension wrappers belong to the extracting library', () async {
    final entry = source('entry', """
import 'other.dart' as other;
int run() {
  final function = other.Public(2).method;
  return function() + other.privateExtraction();
}
""");
    final other = source('other', """
extension Public on int { int method([int value = 3]) => this + value; }
extension Private on int { int _method() => this; }
int privateExtraction() { final function = 7._method; return function(); }
""");
    final program = await AnalysisSession([entry, other])
        .use((input) => Lowering().lower(input).program);
    final run = program.functions.singleWhere((f) => f.target.name == 'run');
    expect(IrInterpreter(program, {}).run(run, []), 12);
    for (final function in program.functions.where(
      (f) => f.target.name.startsWith('<extension-tearoff:'),
    )) {
      expect(function.target.library, function.target.enclosing!.library);
    }
  });

  test(
    'ordinary extension call does not implicitly convert to Function',
    () async {
      final path = source('entry', '''
extension E on int { int call(int value) => this + value; }
int run() { int Function(int) function = 1; return function(2); }
''');
      await expectLater(
        AnalysisSession([path]).use((input) => Lowering().lower(input).program),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'explicit generic binary parameter metadata remains analyzer rejected',
    () async {
      final path = source('entry', '''
class Box<T> { Box(this.value); final T value; }
extension E<T> on Box<T> { T operator +(T other) => other; }
Object? run() => E<int>(Box<int>(1)) + 7;
''');
      await expectLater(
        AnalysisSession([path]).use((input) => Lowering().lower(input).program),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('explicit generic unary result metadata fails closed', () async {
    final path = source('entry', '''
class Box<T> { Box(this.value); final T value; }
extension E<T> on Box<T> { T operator -() => value; }
Object? run() => (-E<int>(Box<int>(1)), 2);
''');
    await expectLater(
      AnalysisSession([path]).use((input) => Lowering().lower(input).program),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('unsubstituted analyzer extension operator result'),
        ),
      ),
    );
  });

  test(
    'declaration-only accessors and operators have no virtual targets',
    () async {
      final path = source('entry', '''
extension E<T> on List<T> {
  T get x => this[0];
  set x(T value) { this[0] = value; }
  T operator [](int index) => this[index];
  void operator []=(int index, T value) { this[index] = value; }
}
''');
      final program = await AnalysisSession([path])
          .use((input) => Lowering().lower(input).program);
      expect(program.classes, isEmpty);
      expect(program.functions.length, 4);
      for (final function in program.functions) {
        expect(function.target.kind, FunctionKind.function);
        expect(function.target.owner, isNull);
        expect(function.target.signature.parameters, isNotEmpty);
        expect(function.target.typeParameters.length, 1);
      }
    },
  );

  test('dynamic invocation never selects an extension', () async {
    final path = source('entry', '''
extension E on int { int m() => this; }
Object? run() { dynamic value = 1; return value.m(); }
''');
    final program = await AnalysisSession([path])
        .use((input) => Lowering().lower(input).program);
    final run = program.functions.singleWhere((f) => f.target.name == 'run');
    expect(
      run.blocks.expand((b) => b.instructions).whereType<DynamicDispatch>(),
      hasLength(1),
    );
    expect(
      run.blocks.expand((b) => b.instructions).whereType<DirectCall>(),
      isEmpty,
    );
  });
}
