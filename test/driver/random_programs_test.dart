@TestOn('mac-os')
@Tags(['native'])
@Timeout.factor(10)
library;

import 'package:test/test.dart';

import '../image/support.dart' show skipExecution;
import '../support/programs.dart';
import 'random_async.dart';
import 'random_patterns.dart';

void main() {
  for (var seed = 0; seed < 4; seed++) {
    test('random patterns, seed $seed', () async {
      await compareGenerated(RandomPatterns(seed).generate());
    }, skip: skipExecution);

    test('random async functions, seed $seed', () async {
      await compareGenerated(RandomAsync(seed).generate());
    }, skip: skipExecution);
  }
}
