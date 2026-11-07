import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';

void main() {
  test('external declarations retain Dart defaults and identities without invented bodies or storage', () async {
    final program = await CheckedLibraries.read([
      'test/lowering/fixtures/externals.dart',
    ], Lowering.lower);
    expect(program.externals, hasLength(11));
    expect(program.functions.map((f) => f.target.name), ['use']);
    expect(program.globals, isEmpty);
    final api = program.classes.single;
    expect(api.fields, isEmpty);
    expect(api.constructors.keys, unorderedEquals(['new', 'named']));
    expect(
      api.members.keys.map((m) => (m.name, m.kind)),
      unorderedEquals([
        ('value', FunctionKind.getter),
        ('value', FunctionKind.setter),
        ('call', FunctionKind.method),
      ]),
    );
    final sum = program.externals.singleWhere((f) => f.target.name == 'sum');
    expect(
      sum.defaults[1]!.structuralKey,
      const Constant.integer(2).structuralKey,
    );
    final library = sum.target.library;
    final runner = FixtureRunner(program, {
      (library, 'identity'): (int value) => value,
    });
    expect(runner.run(program.functions.single, []), 4);
    for (final target in api.constructors.values.followedBy(
      api.members.values,
    )) {
      expect(program.implementationOf(target), isA<IrExternal>());
    }
  });
}
