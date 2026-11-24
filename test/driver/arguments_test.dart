@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(4)
library;

import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/new_compiler.dart';

/// Checks that [source] prints for each of [commands] what it does officially.
void _agrees(String name, String source, List<List<String>> commands) =>
    test(name, () async {
      final directory = writeSources({'main.dart': source});
      final path = '${directory.path}/main.dart';
      final program = '${directory.path}/program';
      writeProgram(await compileProgram(path), program);
      for (final arguments in commands) {
        final official = await Process.run('$hostSdk/bin/dart', [
          'run',
          path,
          ...arguments,
        ]);
        final compiled = await Process.run(program, arguments);
        expect(compiled.stdout, official.stdout, reason: '$arguments');
        expect(compiled.exitCode, official.exitCode, reason: '$arguments');
      }
    }, skip: skipExecution);

const _some = [
  <String>[],
  ['a'],
  ['', 'two words', '-x', '--y=z', 'é', '中文😀', '\t"quoted"'],
];

void main() {
  _agrees('main gets the arguments of the program', r'''
void main(List<String> arguments) {
  print(arguments.length);
  for (final argument in arguments) print('${argument.length} $argument');
  print(arguments.runtimeType);
  try { arguments.add('x'); print(arguments.length); } catch (e) { print(e); }
  try { arguments[0] = 'y'; print(arguments); } catch (e) { print('$e'.split(':').first); }
}
''', _some);

  _agrees('main can take them as other types', r'''
void main(Object? arguments, [dynamic message]) {
  print(arguments);
  print(message);
}
''', _some);

  _agrees('main can wait', r'''
Future<int> main(dynamic arguments, message) async {
  print(message);
  await null;
  print(arguments.join('|'));
  return 7;
}
''', _some);

  _agrees(
    'main can leave them out',
    r'''
void main([List<String>? arguments = const ['none'], Object? more = 3]) {
  print(arguments);
  print(more);
}
''',
    [
      <String>[],
      ['b'],
    ],
  );
}
