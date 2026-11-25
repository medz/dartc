import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/programs.dart';
import 'random_dart.dart';

/// Runs [body], telling what it throws.
String _caught(String body) =>
    '  try { $body }\n'
    "  on C3 { print('!C3'); } on C1 { print('!C1'); }\n"
    "  on K { print('!K'); } on C0 { print('!C0'); }\n"
    '  on UnsupportedError catch (e) { print(e); }\n'
    '  on TypeError catch (e) { print(e); }\n'
    "  on Error { print('!E'); }\n";

/// A program that prints what random functions give.
String _randomFunctions(int seed) {
  final generator = RandomDart(seed);
  final functions = generator.generate(25);
  final checks = [
    for (final (call, _) in generator.calls) _caught('print($call);'),
  ];
  return '$functions\nvoid main() {\n${checks.join()}}';
}

/// Compares random functions made from [seeds] with the official Dart.
void compareFunctions(Iterable<int> seeds) {
  for (final seed in seeds) {
    test('random functions, seed $seed', () async {
      await compareGenerated(_randomFunctions(seed));
    }, skip: skipExecution);
  }
}
