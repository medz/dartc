@Tags(['assets', 'native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/numeric_boxes.dart' as sdk;
import 'fixtures/numeric_boxes_ffi.dart';

void main() {
  test('computed nullable numbers survive calls and repeated collection', () {
    final native = NumericBoxes();
    addTearDown(native.close);
    for (final count in [0, 10000]) {
      for (final value in [
        -0x8000000000000000,
        -1,
        0,
        42,
        0x7fffffffffffffff,
      ]) {
        expect(native.heldInteger(value, count), sdk.heldInteger(value, count));
      }
      for (final value in [
        0.0,
        -0.0,
        1.25,
        double.infinity,
        double.negativeInfinity,
      ]) {
        int bits(double number) =>
            (ByteData(8)..setFloat64(0, number)).getUint64(0);
        expect(
          bits(native.heldFloating(value, count)),
          bits(sdk.heldFloating(value, count)),
        );
      }
    }
    for (final select in [0, 1]) {
      expect(native.optional(42, select), sdk.optional(42, select));
    }
  });

  test(
    'an untaken boxed branch needs no mapping even when mappings fail',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/boxing_null_entry')
            .absolute
            .path,
        [],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
    },
    skip: !Platform.isLinux,
  );
}
