@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/object_values_ffi.dart';

void main() {
  test(
    'constant fields and references survive calls, stack arguments and loops',
    () {
      final values = ObjectValues();
      addTearDown(values.close);
      for (final select in [-1, 0, 1, 2]) {
        expect(values.integer(select), (select > 0 ? 40 : -7) + 123);
        expect(values.floating(select), select > 0 ? 2.5 : -0.0);
        if (select <= 0) {
          expect(1 / values.floating(select), double.negativeInfinity);
        }
        expect(values.boolean(select), select > 0 ? 1 : 0);
        expect(values.checkNull(select), select == 0 ? 1 : 0);
      }
      expect(values.nested(), 40);
      expect(values.stack(), 5 * 40 - 4 * 7);
      for (final count in [0, 1, 2, 31, 32, 99]) {
        expect(values.rotate(count), count.isEven ? 40 : -7);
      }
    },
  );
}
