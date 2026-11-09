import 'dart:io';

import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  test('unmodeled existing SDK members are not reported as missing', () async {
    final directory = Directory.systemTemp.createTempSync('dartc-dynamic-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/entry.dart')
      ..writeAsStringSync(
        "Object? f() { dynamic value = <int>[1, 2]; return value.join(','); }",
      );
    final program = await AnalysisSession([file.path])
        .use((input) async => (await Lowering().lower(input)).program);
    final entry = program.functions.singleWhere((f) => f.target.name == 'f');
    expect(
      () => IrInterpreter(program, {}).run(entry, []),
      throwsUnsupportedError,
    );
  });
}
