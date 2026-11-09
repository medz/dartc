@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/data_ffi.dart';

void main() {
  for (final asset in ['linker/data', 'linker/archive_data']) {
    test('$asset preserves data identity, initialization and writes', () {
      final library = DataLibrary(asset), storage = StorageLibrary();
      addTearDown(library.close);
      addTearDown(storage.close);
      expect(library.readConstant(), 37);
      expect(library.readLocal(), 17);
      expect(library.contains('constant'), isFalse);
      expect(library.contains('private_data'), isFalse);
      expect(library.state.value, 5);
      expect(library.counter.value, 0);
      var state = 5, counter = 0;
      for (final value in [
        7,
        -19,
        -0x8000000000000000,
        0x7fffffffffffffff,
        0,
      ]) {
        state += value;
        counter += value;
        expect(library.updateState(value), state);
        expect(library.updateCounter(value), counter);
        expect(library.state.value, state);
        expect(library.counter.value, counter);
      }
      library.state.value = 91;
      library.counter.value = -3;
      expect(library.updateState(1), 92);
      expect(library.updateCounter(1), -2);
      expect(storage.state.value, 5);
      expect(storage.counter.value, 0);
      storage.state.value = 73;
      expect(library.state.value, 92);
    });
  }
}
