@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/object_text.dart' as sdk;
import 'fixtures/core_collections.dart' as collections;
import 'fixtures/object_text_ffi.dart';

void main() {
  late ObjectText native;
  setUpAll(() {
    native = ObjectText();
    addTearDown(native.close);
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
        for (var mode = 0; mode < 4; mode++) {
          for (final digits in [0, 1, 6, 17, 20]) {
            if (mode == 3 && digits == 0) continue;
            expect(
              native.format(value, mode, digits),
              sdk.formatDouble(value, mode, digits),
              reason: '$value/$mode/$digits',
            );
          }
        }
      }
      expect(() => native.format(1, 1, 21), throwsRangeError);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
  ];
  for (var i = 0; i < cases.length; i++) {
    test(
      cases[i],
      () => expect(native.collection(i), collections.collectionText(i)),
    );
  }
}
