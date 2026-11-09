import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/mixin_type_environments.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async =>
        fixture = await FixtureComparison.load('mixin_type_environments'),
  );
  test(
    'generic class and superclass arguments survive mixin layers and closures',
    () {
      fixture.compare('genericOwners', [], sdk.genericOwners);
      fixture.compare('genericAliases', [], sdk.genericAliases);
      fixture.compare('genericMixins', [], sdk.genericMixins);
      fixture.compare('genericSuper', [], sdk.genericSuper);
      fixture.compare('covariance', [], sdk.covariance);
      fixture.compare('abstractMembers', [], sdk.abstractMembers);
      fixture.compare('inheritedCovariance', [], sdk.inheritedCovariance);
      fixture.compare('constants', [], sdk.constants);
      fixture.compare('nested', [], sdk.nested);
    },
  );
}
