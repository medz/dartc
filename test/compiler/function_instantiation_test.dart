@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/function_instantiation_ffi.dart';

void main() {
  late FunctionInstantiation native;
  setUpAll(() {
    native = FunctionInstantiation();
    addTearDown(native.close);
  });

  test(
    'explicit and inferred instantiations preserve constant function identity',
    () {
      for (final count in [0, 40000]) {
        expect(native.staticFunctions(count), 23418111);
        expect(native.constructors(count), 412111);
      }
    },
  );
  test(
    'instantiated closures share captures but retain origin and type arguments',
    () {
      for (final count in [0, 40000]) {
        expect(native.closures(count), 1361117);
      }
    },
  );
  test('instantiated methods retain receiver, owner environment and runtime signature', () {
    for (final count in [0, 40000]) {
      expect(native.methods(count), 11234111);
    }
  });
  test('instantiated calls preserve throwing behavior and cleanup', () {
    for (final count in [0, 40000]) {
      expect(native.exceptions(count), 245);
    }
  });
  test('constructor tear-offs retain lexical types, aliases and defaults', () {
    for (final count in [0, 40000]) {
      expect(native.lexicalConstructors(count), 1179746);
      expect(native.constructorFailures(count), 12450);
    }
  });
  test(
    'lexical constructor values survive collection across native entries',
    () {
      for (final count in [0, 40000]) {
        expect(native.keepConstructor(count), 1);
        expect(native.callConstructor(count), 47);
      }
    },
  );
}
