@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/layout.dart';
import 'package:test/test.dart';

import 'fixtures/exceptions_ffi.dart';
import 'fixtures/stack_roots_ffi.dart' show RootVisitor;

void main() {
  test('local catch preserves a loaded exception and other live values', () {
    final native = ExceptionCalls();
    addTearDown(native.close);
    expect(native.local(), 321);
  });

  test('exception identity, traces and Error storage survive rethrow and collection', () {
    const payload = ObjectHeader.fieldsOffset ~/ ObjectHeader.alignment;
    final native = ExceptionCalls();
    addTearDown(native.close);
    final maps = <int, StackRoots>{};
    for (var i = 0; i < native.table.value; i++) {
      final index = (StackMapTable.entries + i * StackMapTable.entrySize) ~/ 8;
      final pc = native.table[index + StackMapTable.pc ~/ 8];
      final offset = native.table[index + StackMapTable.record ~/ 8] ~/ 8;
      final count = native.table[offset + StackMapRecord.rootCount ~/ 8];
      maps[pc] = StackRoots(
        native.table[offset + StackMapRecord.callerStack ~/ 8],
        native.table[offset + StackMapRecord.returnAddress ~/ 8],
        [
          for (var j = 0; j < count; j++)
            native.table[offset + StackMapRecord.roots ~/ 8 + j],
        ],
      );
    }
    int errorTraceSlot(Pointer<Uint64> object) {
      final descriptor = Pointer<Uint64>.fromAddress(object.value);
      return descriptor[ObjectDescriptor.traceBase +
              descriptor[ObjectDescriptor.referenceCount]] ~/
          ObjectHeader.alignment;
    }

    List<int> trace(int address) {
      final result = <int>[], seen = <int>{};
      while (address != 0) {
        expect(seen.add(address), isTrue, reason: 'Cyclic captured trace');
        if (seen.length > 20) fail('Captured trace did not end.');
        final node = Pointer<Uint64>.fromAddress(address);
        expect(
          maps.containsKey(node[payload]),
          isTrue,
          reason: 'Unknown captured PC',
        );
        result.add(node[payload]);
        address = node[payload + 1];
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
        (Object, StackTrace)? failure;
        final visitor = NativeCallable<RootVisitor>.isolateLocal((
          int pc,
          Pointer<Uint64> sp,
        ) {
          try {
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
            final payloads = roots.where((address) {
              if (address == 0) return false;
              final object = Pointer<Uint64>.fromAddress(address);
              final slot = isError ? errorTraceSlot(object) - 1 : payload;
              return slot >= payload && object[slot] == 123;
            }).toList();
            final traces = roots
                .where(
                  (address) =>
                      address != 0 &&
                      maps.containsKey(
                        Pointer<Uint64>.fromAddress(address)[payload],
                      ),
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
              final slot = errorTraceSlot(object);
              expect(trace(object[slot]), originalTrace);
              expect(object[slot] == traces.single, calls < 2);
            }
            calls++;
            return 0;
          } catch (error, trace) {
            failure ??= (error, trace);
            return -1;
          }
        }, exceptionalReturn: -1);
        try {
          expect(
            run(count, native.probe.address, visitor.nativeFunction.address),
            123,
          );
          if (failure case (final error, final trace)) {
            Error.throwWithStackTrace(error, trace);
          }
          expect(calls, 3);
        } finally {
          visitor.close();
        }
      }
    }
  });
}
