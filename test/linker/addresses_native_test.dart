@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/addresses_ffi.dart';
import 'fixtures/memory_protection.dart';

void main() {
  test('a pointer-only library remains read-only after loading', () {
    final library = AddressLibrary('addresses_constant');
    addTearDown(library.close);
    final table = library.table('table');
    expect(table[0].value, 37);
    expect(table[1].address, table.address);
    expect(memoryProtection(table), 1);
  });
  for (final asset in [
    'addresses_static',
    'addresses_archive',
    'addresses_shared',
  ]) {
    test('$asset preserves function and storage addresses after loading', () {
      final library = AddressLibrary(asset);
      final provider = asset == 'addresses_shared'
          ? AddressLibrary('addresses_provider')
          : library;
      addTearDown(library.close);
      if (provider != library) addTearDown(provider.close);
      for (final name in ['function', 'constant', 'state', 'zero']) {
        expect(library.address(name), provider.symbol(name));
      }
      final table = library.table('table');
      final mutable = library.table('mutable_table');
      expect(memoryProtection(table), 1);
      expect(memoryProtection(mutable), 3);
      for (final slots in [table, mutable]) {
        for (final (i, name) in [
          'function',
          'constant',
          'state',
          'zero',
        ].indexed) {
          expect(slots[i], provider.symbol(name));
        }
        expect(slots[4].value, 29);
        expect(slots[5].address, table.address);
        expect(slots[6].address, mutable.address);
        expect(
          slots[0]
              .cast<NativeFunction<Int64 Function()>>()
              .asFunction<int Function()>()(),
          42,
        );
      }
      mutable[0] = provider.symbol('state');
      expect(mutable[0], provider.symbol('state'));
      expect(table[0], provider.symbol('function'));
      expect(library.call(), 42);
      expect(
        library
            .address('function')
            .cast<NativeFunction<Int64 Function()>>()
            .asFunction<int Function()>()(),
        42,
      );
      expect(library.address('constant').value, 37);
      expect(library.address('state').value, 7);
      expect(library.address('zero').value, 0);
      expect(library.address('local').value, 17);
      for (final name in ['state', 'zero']) {
        final address = library.address(name), symbol = provider.symbol(name);
        address.value = -0x8000000000000000;
        expect(symbol.value, -0x8000000000000000);
        symbol.value = 0x7fffffffffffffff;
        expect(address.value, 0x7fffffffffffffff);
      }
      expect(library.read(), 0x7fffffffffffffff);
      expect(library.write(-0x8000000000000000), -0x8000000000000000);
      expect(provider.symbol('state').value, -0x8000000000000000);
      provider.symbol('state').value = 91;
      expect(library.read(), 91);
      library.address('local').value = 19;
      expect(library.address('local').value, 19);
      expect(library.address('constant').value, 37);
    });
  }
}
