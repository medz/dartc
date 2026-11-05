import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_named_order.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_named_order');
  });
  test('extension declaration order agrees with defaults and body slots', () {
    for (final x in [0, 3]) {
      fixture.compare('ordinary', [x], () => sdk.ordinary(x));
      fixture.compare('extensionType', [x], () => sdk.extensionType(x));
      fixture.compare('genericMethods', [x], () => sdk.genericMethods(x));
    }
    fixture.compare('constructors', [], sdk.constructors);
  });
}
