@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../runtime/fixtures/decimal_text.dart';
import 'fixtures/object_text.dart' as sdk;
import 'fixtures/core_collections.dart' as collections;
import 'fixtures/core_conversion.dart' as conversion;
import 'fixtures/object_text_ffi.dart';

void main() {
  late ObjectText native;
  setUpAll(() {
    native = ObjectText();
    addTearDown(native.close);
  });
  test('double and num parsing preserve values, types and invalid input', () {
    for (final source in decimalInputs) {
      for (var mode = 0; mode < 8; mode++) {
        num? expected;
        var status = 2;
        try {
          expected = sdk.parseNumber(source, mode);
          status = expected == null ? 2 : (expected is int ? 1 : 0);
        } on FormatException {
          status = 3;
        }
        final (actualStatus, actual) = native.parse(source, mode);
        final reason = '$source/$mode';
        expect(actualStatus, status, reason: reason);
        if (expected?.isNaN == true) {
          expect(actual?.isNaN, isTrue, reason: reason);
        } else {
          expect(actual, expected, reason: reason);
          expect(actual?.isNegative, expected?.isNegative, reason: reason);
        }
      }
    }
    for (final MapEntry(key: source, value: expected)
        in decimalRounding.entries) {
      final (status, value) = native.parse(source, 0);
      expect(status, 0, reason: source);
      final bits = ByteData(8)..setFloat64(0, value as double);
      expect(bits.getUint64(0), expected, reason: source);
    }
  });

  test(
    'floating text preserves exact rounding through compiled Dart algorithms',
    () {
      for (final value in <double>[
        0,
        -0.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        double.minPositive,
        double.maxFinite,
        2.2250738585072014e-308,
        0.1,
        1.25,
        2.55,
        1e-7,
        1e-6,
        1e20,
        1e21,
        9007199254740992,
        -1234567.125,
      ]) {
        for (var mode = 0; mode < 7; mode++) {
          final precisions = mode == 0 || mode == 4
              ? const [0]
              : const [-1, 0, 1, 6, 17, 20, 21, 22];
          for (final digits in precisions) {
            if ((mode == 1 || mode == 2 || mode == 5) &&
                    (digits < 0 || digits > 20) ||
                (mode == 3 || mode == 6) && (digits < 1 || digits > 21)) {
              expect(
                () => native.format(value, mode, digits),
                throwsRangeError,
                reason: '$value/$mode/$digits',
              );
              continue;
            }
            expect(
              native.format(value, mode, digits),
              sdk.formatDouble(value, mode, digits),
              reason: '$value/$mode/$digits',
            );
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('type text retains nested arguments, nullability and call shapes', () {
    for (var mode = 0; mode < 16; mode++) {
      final expected = switch (mode) {
        4 => 'String Function(int, [bool])',
        5 => 'int Function({required String name, double value})',
        6 => 'X0 Function<X0 extends num>(X0)',
        7 => '(String Function())?',
        12 => 'X0 Function<X0 extends num>(X1 Function<X1 extends X0>(X1, X0))',
        13 => '(int,)',
        _ => sdk.typeText(mode),
      };
      expect(native.typeText(mode), expected, reason: 'type $mode');
    }
  });
  test('dynamic calls preserve lookup, shapes, checks and side effects', () {
    for (var mode = 0; mode < 76; mode++) {
      expect(
        native.dispatchText(mode),
        mode == 67 ? '111|[]' : sdk.dispatchText(mode),
        reason: 'dispatch $mode',
      );
    }
  });
  const cases = [
    'object dispatch, super and nullable tear-offs',
    'StringBuffer writes, UTF-16 length and reset',
    'list mutation, overlapping ranges and default sort',
    'self append and fixed-length lists',
    'unmodifiable and constant list mutations',
    'ordered sets and set algebra',
    'custom equality and canonical set values',
    'nullable, constant and unmodifiable sets',
    'immutable maps snapshot their input and reject empty writes',
    'map factories and transformations',
    'lazy iterable adapters and reductions',
    'recursive collection formatting and member formatting',
    'checked collection spreads',
    'cast views check writes',
    'identity sets and maps',
    'hash sets and concurrent modification',
    'standard errors format escaped values and context',
    'interpolation and extracted methods retain effects',
    'StringBuffer compaction, UTF-16 buffering and reuse after errors',
    'ordered collection deletion, collisions, copying and callback mutation',
    'list factories, shrinking, regrowing and mixed-value joins',
  ];
  for (var i = 0; i < cases.length; i++) {
    test(
      cases[i],
      () => expect(native.collection(i), collections.collectionText(i)),
    );
  }
  test('NoSuchMethodError uses SDK formatting for methods and accessors', () {
    expect(native.collection(22), collections.collectionText(22));
  });
  test('fixed lists reject invalid skips and insufficient range input', () {
    expect(native.collection(21), 'range/short/short');
  });

  void compareConversion(
    String input,
    conversion.Conversion mode, [
    int split = 0,
  ]) => expect(
    native.convert(input, mode, split),
    conversion.conversionText(input, mode, split),
    reason: '$mode/$split/$input',
  );

  const documents = [
    'null',
    'true',
    '-0.0',
    '[0,-1,9007199254740993,9223372036854775808,1e309,5e-324]',
    r'{"a":[1,true,null],"s":"a\n\t\u0000\ud83d\ude42","a":2}',
    r'["\ud800","\udc00","𐀀",{},[]]',
    ' { "first": {"nested": 1}, "second": [2, 3] } ',
  ];
  test(
    'JSON values, numeric boundaries, escaping, indentation and reviver',
    () {
      for (final input in documents) {
        for (final mode in <conversion.Conversion>[.json, .pretty, .reviver]) {
          compareConversion(input, mode);
        }
      }
      expect(native.convert('{"x":1,"x":2}', .json), '{"x":2}');
      expect(
        native.convert('{"a":[1,2]}', .reviver),
        '{"a":[2,3]}|[0,1,"a",null]',
      );
    },
  );

  test('JSON chunks preserve token boundaries and reject malformed input', () {
    for (final input in [
      ...documents,
      '',
      '01',
      '1.',
      '[true false]',
      '[1,]',
      '{"x":}',
      'true false',
      r'"\u12x4"',
      '"line\nfeed"',
      r'"\ud800',
    ]) {
      compareConversion(input, .json);
      for (var split = 0; split <= input.length; split++) {
        compareConversion(input, .jsonChunks, split);
        expect(
          native.convert(input, .jsonFinalSlice, split),
          conversion.conversionText(input, .jsonChunks, split),
          reason: 'final slice/$split/$input',
        );
      }
    }
  });

  test('UTF-8 encoding and error strings retain UTF-16 input', () {
    for (final input in [
      '',
      'plain text',
      'é\u0100中🙂',
      '\u0000\b\t\n\r\f"\\',
      '\ud800x\udc00',
    ]) {
      compareConversion(input, .encodeUtf8);
      compareConversion(input, .safeString);
      compareConversion(input, .customJson);
    }
  });

  test('UTF-8 decoding handles BOM, split sequences and malformed bytes', () {
    for (final bytes in <List<int>>[
      [],
      [0, 65, 127],
      [0xef, 0xbb, 0xbf, 65],
      utf8.encode('éĀ中🙂'),
      [0xc0, 0xaf],
      [0xed, 0xa0, 0x80],
      [0xf4, 0x90, 0x80, 0x80],
      [0x80, 65, 0xff],
      [0xf0, 0x9f],
      [0xef, 0xbb],
    ]) {
      final input = jsonEncode(bytes);
      compareConversion(input, .utf8);
      compareConversion(input, .malformedUtf8);
      for (var split = 0; split <= bytes.length; split++) {
        compareConversion(input, .utf8Chunks, split);
        compareConversion(input, .malformedUtf8Chunks, split);
      }
    }
  });

  test('fused UTF-8 and JSON conversion retains chunks and failures', () {
    for (final document in [...documents, '[1,]', r'"\u12x4"']) {
      final bytes = utf8.encode(document);
      final input = jsonEncode(bytes);
      compareConversion(input, .fusedJson);
      for (var split = 0; split <= bytes.length; split++) {
        compareConversion(input, .fusedJsonChunks, split);
      }
    }
  });

  test(
    'JSON rejects cycles, non-string keys, non-finite values and failed hooks',
    () {
      for (var kind = 0; kind < 5; kind++) {
        compareConversion('failure', .invalidJsonObject, kind);
      }
    },
  );
}
