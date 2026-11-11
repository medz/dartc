@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/expandos.dart' as sdk;
import 'fixtures/expandos_ffi.dart';

void main() {
  test('Expando properties use identity, preserve values and reclaim cleared entries', () {
    final native = Expandos();
    addTearDown(native.close);
    for (final count in [0, 1, 64, 1200]) {
      final actual = native.properties(count);
      expect(actual, sdk.properties(count));
      expect(actual, count * count / 2);
    }
    final checked = native.checkedValues();
    expect(checked, sdk.checkedValues());
    expect(checked, 1);
    for (final (integer, floating) in [
      (1, 1.25),
      (-1, -0.0),
      (0x7fffffffffffffff, double.nan),
    ]) {
      expect(native.identityHashes(integer, floating), 1);
    }
  });

  test('conditional chains require live keys and live Expando owners', () {
    final native = Expandos();
    addTearDown(native.close);
    for (final mode in [0, 1, 2]) {
      native.createGraph(mode);
      expect(native.observeGraph(0), mode == 0 ? -1 : 1);
      expect(native.observeGraph(1), mode == 1 ? 3 : -1);
      native.releaseGraph();
      expect(native.observeGraph(0), -1);
      expect(native.observeGraph(1), -1);
    }
  });

  test('invalid keys are rejected on reads and null writes', () {
    final native = Expandos();
    addTearDown(native.close);
    for (var kind = 0; kind < 6; kind++) {
      final expected = kind == 5 ? 4 : 2;
      expect(sdk.rejects(kind), expected);
      expect(native.rejects(kind), expected);
    }
  });
}
