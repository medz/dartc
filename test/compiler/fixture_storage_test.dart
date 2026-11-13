@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/exceptions_ffi.dart';
import 'fixtures/managed_objects_ffi.dart';

void main() {
  test('native fixtures keep independent scratch state', () {
    final exceptions = Exceptions(), objects = ManagedObjects();
    addTearDown(exceptions.close);
    addTearDown(objects.close);

    exceptions.effects.value = 17;
    objects.output.value = 29;
    expect(exceptions.effects.value, 17);
    expect(objects.output.value, 29);

    exceptions.effects.value = 41;
    expect(objects.output.value, 29);
  });
}
