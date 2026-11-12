import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  test('external declarations retain Dart defaults and identities without invented bodies or storage', () async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/externals.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    expect(
      program.externals.where((f) => f.target.library?.scheme != 'dart'),
      hasLength(11),
    );
    expect(
      program.functions
          .where((f) => f.target.library?.scheme != 'dart')
          .map((f) => f.target.name),
      ['use'],
    );
    expect(program.globals.where((g) => g.library.scheme != 'dart'), isEmpty);
    final api = program.classes.singleWhere(
      (c) => c.type.library?.scheme != 'dart',
    );
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
    final library = sum.target.library!;
    final runner = IrInterpreter(program, {
      (library, 'identity'): (int value) => value,
    });
    expect(
      runner.run(
        program.functions.singleWhere((f) => f.target.library == library),
        [],
      ),
      4,
    );
    for (final target in api.constructors.values.followedBy(
      api.members.values,
    )) {
      expect(program.implementationOf(target), isA<IrExternal>());
    }
  });
}
