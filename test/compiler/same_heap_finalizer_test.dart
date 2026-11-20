@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'shared entries collect a witness while keeping the node chain live',
    () {
      final assets = NativeAssets(Target.host());
      final provider = assets.open('compiler/native_finalizer_callback');
      try {
        // The other native-finalizer suite uses words 0 and 1 of this 64-byte buffer.
        final counter = provider.lookup<Int64>('resource_state') + 2;
        counter.value = 0;
        final callback = provider.lookup<NativeFinalizerFunction>(
          'resource_released',
        );
        late int afterRegister, during, first, last, end;
        final library = assets.open('compiler/same_heap_finalizer');
        try {
          final register = library
              .lookupFunction<
                Void Function(Pointer<NativeFinalizerFunction>, Pointer<Int64>),
                void Function(Pointer<NativeFinalizerFunction>, Pointer<Int64>)
              >('registerWitness');
          final grow = library
              .lookupFunction<
                Int64 Function(Int64, Pointer<Int64>),
                int Function(int, Pointer<Int64>)
              >('grow');
          final read = library
              .lookupFunction<Int64 Function(Int64), int Function(int)>('read');
          register(callback, counter);
          afterRegister = counter.value;
          const count = 4096;
          during = grow(count, counter);
          first = read(0);
          last = read(count - 1);
          end = read(count);
        } finally {
          library.close();
        }
        expect(
          (afterRegister, during, first, last, end, counter.value),
          (0, 1, 4095, 0, -1, 1),
          reason: 'counts at registration/collection, chain head/tail/end, count at unload',
        );
      } finally {
        provider.close();
      }
    },
  );
}
