import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('compiled exports preserve FFI argument and result types in headers', () {
    final header = NativeAssets(Target.host())
        .file('compiler/arithmetic.h')
        .readAsStringSync();
    expect(
      header,
      stringContainsInOrder([
        '#include <stdint.h>',
        'extern "C" {',
        'int64_t native_add(int64_t, int64_t);',
        'int64_t reverse(int64_t, int64_t);',
        'int64_t twice(int64_t);',
        'int64_t increment(int64_t);',
        'int64_t literal(void);',
        'int64_t mixed(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);',
      ]),
    );
  });
}
