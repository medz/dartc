import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartc/src/source/inflate.dart';
import 'package:test/test.dart';

Uint8List _deflate(List<int> data, {int level = 6, int strategy = 0}) =>
    Uint8List.fromList(
      ZLibCodec(raw: true, level: level, strategy: strategy).encode(data),
    );

void main() {
  test('gives what was compressed', () {
    final random = Random(3);
    List<int> bytes(int count, int Function(int i) limit) => [
      for (var i = 0; i < count; i++) random.nextInt(limit(i)),
    ];
    // What is far away is copied too.
    final start = bytes(32000, (_) => 256);
    final texts = <List<int>>[
      [],
      [7],
      utf8.encode('the same, the same, the same'),
      List.filled(100000, 5),
      bytes(70000, (_) => 256),
      bytes(70000, (_) => 4),
      bytes(70000, (i) => 1 + i ~/ 300),
      [...start, ...start, ...start.reversed, ...start],
    ];
    for (final text in texts) {
      for (final level in [0, 1, 6, 9]) {
        for (final strategy in const [
          ZLibOption.strategyDefault,
          ZLibOption.strategyHuffmanOnly,
          ZLibOption.strategyFixed,
        ]) {
          final data = _deflate(text, level: level, strategy: strategy);
          expect(inflate(data), text);
        }
      }
    }
  });

  test('what is not whole is refused', () {
    final data = _deflate(utf8.encode('the same, the same, the same'));
    for (var length = 0; length < data.length; length++) {
      expect(
        () => inflate(Uint8List.sublistView(data, 0, length)),
        throwsFormatException,
        reason: '$length',
      );
    }
  });

  test('what is not compressed is refused', () {
    for (final data in [
      // A kind of block that there is not.
      [7],
      // Lengths that do not agree.
      [1, 5, 0, 5, 0],
      // A copy of what is before the start.
      [0x03, 0x02],
    ]) {
      expect(() => inflate(Uint8List.fromList(data)), throwsFormatException);
    }
  });

  test('random bytes end', () {
    final random = Random(9);
    for (var round = 0; round < 3000; round++) {
      final data = Uint8List.fromList([
        for (var i = random.nextInt(200); i > 0; i--) random.nextInt(256),
      ]);
      try {
        inflate(data);
      } on FormatException {
        continue;
      }
    }
  });
}
