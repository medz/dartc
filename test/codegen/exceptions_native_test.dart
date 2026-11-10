@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/layout.dart';
import 'package:test/test.dart';

import 'fixtures/exceptions_ffi.dart';
import 'fixtures/stack_roots_ffi.dart' show RootVisitor;

void main() {
  test('exception identity, traces and Error storage survive rethrow and collection', () {
    final native = ExceptionCalls();
    addTearDown(native.close);
    final maps = <int, StackRoots>{};
    var offset = 1;
    for (var i = 0; i < native.table.value; i++) {
      final count = native.table[offset + 3];
      maps[native.table[offset]] = StackRoots(
        native.table[offset + 1],
        native.table[offset + 2],
        [for (var j = 0; j < count; j++) native.table[offset + 4 + j]],
      );
      offset += 4 + count;
    }
    List<int> trace(int address) {
      final result = <int>[], seen = <int>{};
      while (address != 0) {
        expect(seen.add(address), isTrue, reason: 'Cyclic captured trace');
        if (seen.length > 20) fail('Captured trace did not end.');
        final node = Pointer<Uint64>.fromAddress(address);
        expect(
          maps.containsKey(node[1]),
          isTrue,
          reason: 'Unknown captured PC',
        );
        result.add(node[1]);
        address = node[2];
      }
      return result;
    }

    for (final (run, isError) in [
      (native.plain, false),
      (native.error, true),
    ]) {
      for (final count in [0, 40000]) {
        var calls = 0;
        List<int>? originalTrace;
        final visitor = NativeCallable<RootVisitor>.isolateLocal((
          int pc,
          Pointer<Uint64> sp,
        ) {
          final roots = <int>[];
          for (var depth = 0; depth < 20; depth++) {
            final record = maps[pc]!;
            roots.addAll([
              for (final offset in record.offsets) sp[offset ~/ 8],
            ]);
            if (record.callerStackOffset == 0) break;
            pc = sp[record.returnAddressOffset ~/ 8];
            sp += record.callerStackOffset ~/ 8;
          }
          final payloads = roots
              .where(
                (address) =>
                    address != 0 &&
                    Pointer<Uint64>.fromAddress(address)[1] == 123,
              )
              .toList();
          final traces = roots
              .where(
                (address) =>
                    address != 0 &&
                    maps.containsKey(Pointer<Uint64>.fromAddress(address)[1]),
              )
              .toSet();
          expect(payloads.length, greaterThanOrEqualTo(2));
          expect(payloads.toSet(), hasLength(1));
          expect(traces, hasLength(1));
          final stack = trace(traces.single);
          if (calls == 0) originalTrace = stack;
          expect(stack, calls < 2 ? originalTrace : hasLength(2));
          if (calls < 2) expect(stack, hasLength(5));
          if (isError) {
            final object = Pointer<Uint64>.fromAddress(payloads.first);
            final descriptor = Pointer<Uint64>.fromAddress(object.value);
            final slot = descriptor[2 + descriptor[1]] ~/ 8;
            expect(slot, 2);
            expect(trace(object[slot]), originalTrace);
            expect(object[slot] == traces.single, calls < 2);
          }
          calls++;
          return 0;
        }, exceptionalReturn: -1);
        try {
          expect(
            run(count, native.probe.address, visitor.nativeFunction.address),
            123,
          );
          expect(calls, 3);
        } finally {
          visitor.close();
        }
      }
    }
  });
}
