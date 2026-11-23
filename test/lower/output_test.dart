import 'package:dartc/hir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

HirModule _printing(List<String> texts) => body((block) {
  for (final text in texts) {
    block.add(HirPrint(text));
  }
  return HirReturn();
});

void main() {
  test('texts are written as UTF-8 with a newline', () {
    final run = LoweredRun(_printing(['a', '', 'é😀', 'x\u0000y\n']));
    expect(run.output, 'a\n\né😀\nx\u0000y\n\n');
    expect(run.calls, ['signal[13, 1]', ...List.filled(4, 'write1')]);
    expect(LoweredRun(_printing(['\uD800'])).output, '�\n');
  });

  test('each text is stored once', () {
    final module = lowerProgram(_printing(['a', 'b', 'a']));
    expect(module.data.map((data) => data.bytes), [
      [97, 10],
      [98, 10],
    ]);
    expect(module.data.map((data) => data.writable), everyElement(isFalse));
  });

  test('a program that does not print needs nothing for it', () {
    final module = lowerProgram(body((_) => HirReturn()));
    expect(module.externals, isEmpty);
    expect(module.data, isEmpty);
    expect(module.functions, hasLength(2));
  });

  test('partial writes continue', () {
    for (final size in [1, 2, 3, 100]) {
      final run = LoweredRun(_printing(['hello', 'you']), accept: (_) => size);
      expect(run.output, 'hello\nyou\n');
    }
  });

  test('interrupted writes are repeated', () {
    var count = 0;
    final run = LoweredRun(
      _printing(['hello']),
      accept: (_) => count++ < 3 ? -4 : 2,
    );
    expect(run.output, 'hello\n');
    expect(count, 6);
  });

  test('other errors drop the rest of one text', () {
    for (final error in [-1, -9, -32, -35]) {
      var count = 0;
      final run = LoweredRun(
        _printing(['hello', 'you']),
        accept: (n) => switch (count++) {
          0 => 2,
          1 => error,
          _ => n,
        },
      );
      expect(run.output, 'heyou\n', reason: '$error');
    }
  });

  test('a write accepting nothing does not repeat forever', () {
    expect(LoweredRun(_printing(['a']), accept: (_) => 0).output, isEmpty);
  });
}
