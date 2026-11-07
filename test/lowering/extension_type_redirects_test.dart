import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_type_redirects.dart' as sdk;

void main() {
  test(
    'erased factory redirects preserve defaults and generic construction',
    () async {
      final fixture = await FixtureComparison.load('extension_type_redirects');
      fixture.compare('redirects', [], sdk.redirects);
    },
  );
}
