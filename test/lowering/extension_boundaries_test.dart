import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';

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
      final program = await CheckedLibraries.read([
        entry,
        other,
      ], Lowering.lower);
      final run = program.functions.singleWhere((f) => f.target.name == 'run');
      expect(FixtureRunner(program, {}).run(run, []), 109);
      final markTargets = program.functions.where(
        (f) => f.target.name.endsWith(':method:mark>'),
      );
      expect(markTargets.length, 2);
      expect(markTargets.map((f) => f.target.name).toSet().length, 2);
    },
  );

  for (final (name, declaration, use) in <(String, String, String)>[
    ('getter', 'int get x => this;', '1.x'),
    ('setter', 'set x(int value) {}', '(1.x = 2)'),
    ('operator', 'int operator +(int value) => value;', 'E(1) + 2'),
    ('tear-off', 'int m() => this;', '1.m'),
    ('implicit invocation', 'int call() => this;', '(1)()'),
  ]) {
    test('$name remains an explicit lowering boundary', () async {
      final path = source(
        'entry',
        'extension E on int { $declaration } Object? run() => $use;',
      );
      await expectLater(
        CheckedLibraries.read([path], Lowering.lower),
        throwsUnsupportedError,
      );
    });
  }

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
      final program = await CheckedLibraries.read([path], Lowering.lower);
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
    final program = await CheckedLibraries.read([path], Lowering.lower);
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
