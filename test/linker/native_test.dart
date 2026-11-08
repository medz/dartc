import 'package:test/test.dart';

import 'fixtures/symbols.dart';
import 'fixtures/calls_ffi.dart';
import 'fixtures/values_ffi.dart';

void main() {
  final values = Values();
  tearDownAll(values.close);
  final symbols = Symbols();
  tearDownAll(symbols.close);

  final calls = LinkedCalls();
  tearDownAll(calls.close);
  test(
    'resolves imports and module-local references without exporting helpers',
    () {
      expect(calls.forward(), 42);
      expect(calls.hasSymbol('helper'), isFalse);
      expect(calls.hasSymbol('local'), isFalse);
    },
  );

  test('functions from separate objects are callable', () {
    expect(values.first(), 40);
    expect(values.second(), 2);
  });

  test('large symbol tables resolve prefixes and Unicode names', () {
    for (final MapEntry(:key, :value) in symbolValues.entries) {
      expect(symbols(key), value, reason: key);
    }
    expect(symbols.contains('prefi'), isFalse);
    expect(symbols.contains('fn_700'), isFalse);
  });
}
