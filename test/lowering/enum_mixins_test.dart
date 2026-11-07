import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/enum_mixins.dart' as sdk;

void main() {
  test(
    'enum mixins retain dispatch, constants and actual type arguments',
    () async {
      final fixture = await FixtureComparison.load('enum_mixins');
      fixture.compare('labels', [], sdk.labels);
      fixture.compare('parameters', [], sdk.parameters);
    },
  );
}
