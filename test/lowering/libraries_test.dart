import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('dartc-libraries-');
  });
  tearDown(() => directory.deleteSync(recursive: true));
  String source(String name, String text) {
    final file = File('${directory.path}/$name.dart')..writeAsStringSync(text);
    return file.path;
  }

  Object? run(IrProgram program) => FixtureRunner(
    program,
    {},
  ).run(program.functions.singleWhere((f) => f.target.name == 'run'), []);

  test(
    'reexports and combinators preserve shared getter/setter identity',
    () async {
      final original = source('original', '''
int _value = 2;
int get value => _value;
set value(int next) { _value = next; }
int hidden() => 100;
''');
      source('barrel', "export 'original.dart' show value;");
      source('outer', "export 'barrel.dart' hide hidden;");
      final entry = source('entry', '''
import 'outer.dart' as exposed show value;
import 'original.dart' as original hide hidden;
int run() { exposed.value += 3; return original.value; }
''');
      expect(
        run(await CheckedLibraries.read([entry, original], Lowering.lower)),
        5,
      );
    },
  );

  test('ambiguous names are rejected before lowering', () async {
    source('left', 'int value() => 1;');
    source('right', 'int value() => 2;');
    final entry = source('entry', '''
import 'left.dart';
import 'right.dart';
int run() => value();
''');
    var consumed = false;
    await expectLater(
      CheckedLibraries.read([entry], (input) {
        consumed = true;
      }),
      throwsA(isA<FormatException>()),
    );
    expect(consumed, isFalse);
  });

  test(
    'hidden and private names cannot be selected through a prefix',
    () async {
      source('other', 'int visible() => 1; int _private() => 2;');
      for (final name in ['visible', '_private']) {
        final entry = source('entry', '''
import 'other.dart' as other hide visible;
int run() => other.$name();
''');
        await expectLater(
          CheckedLibraries.read([entry], Lowering.lower),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'conditional import and export use analyzer selected libraries',
    () async {
      final original = source('original', 'int value() => 7;');
      source('alternate', 'int value() => 99;');
      source(
        'barrel',
        "export 'original.dart' if (dartc.test) 'alternate.dart';",
      );
      final entry = source('entry', '''
import 'original.dart' if (dartc.test) 'alternate.dart' as direct;
import 'barrel.dart' as exposed;
int run() => direct.value() + exposed.value();
''');
      final program = await CheckedLibraries.read([
        entry,
        original,
      ], Lowering.lower);
      expect(run(program), 14);
      final calls = program.functions.first.entry.instructions
          .whereType<DirectCall>();
      expect(calls.map((call) => call.target).toSet(), hasLength(1));
    },
  );

  test('file URI and relative imports identify the same library', () async {
    final other = source('other', 'int value() => 6;');
    final entry = source('entry', '''
import '${File(other).uri}' as absolute;
import 'other.dart' as relative;
int run() => absolute.value() + relative.value();
''');
    final program = await CheckedLibraries.read([entry, other], Lowering.lower);
    expect(run(program), 12);
    final calls = program.functions.first.entry.instructions
        .whereType<DirectCall>();
    expect(calls.map((call) => call.target).toSet(), hasLength(1));
  });

  for (final named in [false, true]) {
    test(
      'library and ${named ? 'named' : 'URI'} parts share private declarations',
      () async {
        source('piece', '''
part of ${named ? 'example' : "'entry.dart'"};
int _value() => 11;
''');
        final entry = source('entry', '''
#!/usr/bin/env dart
library ${named ? 'example' : ''};
import 'dart:core';
part 'piece.dart';
int run() => _value();
''');
        final program = await CheckedLibraries.read([entry], Lowering.lower);
        expect(run(program), 11);
        expect(
          program.functions.map((f) => f.target.library).toSet(),
          hasLength(1),
        );
        await expectLater(
          CheckedLibraries.read([
            '${directory.path}/piece.dart',
          ], Lowering.lower),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }

  test('batch does not assemble transitive bodies or select main', () async {
    final other = source('other', 'int value() => 5;');
    final entry = source(
      'entry',
      "import 'other.dart'; void main() { value(); }",
    );
    final program = await CheckedLibraries.read([entry], Lowering.lower);
    expect(program.functions.single.target.name, 'main');
    final call = program.functions.single.entry.instructions
        .whereType<DirectCall>()
        .single;
    expect(call.target.name, 'value');
    expect(
      program.functions.any((f) => identical(f.target, call.target)),
      isFalse,
    );
    final linked = await CheckedLibraries.read([entry, other], Lowering.lower);
    expect(FixtureRunner(linked, {}).run(linked.functions.first, []), isNull);
    expect(linked.functions.map((f) => f.target.name), ['main', 'value']);
  });
}
