@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/native_callbacks.dart';
import 'fixtures/native_callbacks_ffi.dart';

void main() {
  late NativeCallbacks native;
  setUpAll(() {
    native = NativeCallbacks();
    addTearDown(native.close);
  });

  test(
    'escaped callbacks retain state, catch exceptions and allow reentry',
    () {
      final call = native.integer().asFunction<int Function(int)>();
      final before = native.calls();
      expect(call(14), 42);
      expect(call(-1), -73);
      expect(call(3), 9);
      expect(native.alias().asFunction<int Function(int)>()(913), 913);
      final visit = NativeCallable<Visitor>.isolateLocal(
        (Pointer<NativeFunction<Unary>> callback) =>
            callback.asFunction<int Function(int)>()(7),
        exceptionalReturn: -1,
      );
      addTearDown(visit.close);
      expect(native.reenter(visit.nativeFunction), 59);
      final ignore = native.empty().asFunction<void Function(int)>();
      ignore(-5);
      ignore(5);
      expect(native.calls(), before + 6);
    },
  );

  test(
    'mixed register and stack arguments preserve widths and exception values',
    () {
      final call = native
          .mixed()
          .asFunction<
            double Function(
              int,
              double,
              bool,
              double,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
            )
          >();
      expect(call(-7, 1.25, true, 2.5, 1, 2, 3, 4, 5, 6, 7, 8, 9), 41.75);
      expect(call(1, 0, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), -1.25);
      final plain = native.plain().asFunction<double Function(double)>();
      expect(plain(3.5), 1.75);
      expect(plain(-1), -2.5);
      expect(plain(4), 2);
    },
  );

  test(
    'pointer and compound callback results use native storage contracts',
    () {
      final pointer = native.allocate(sizeOf<Int64>()).cast<Int64>();
      if (pointer == nullptr) {
        throw StateError('Cannot allocate fixture storage.');
      }
      pointer.value = 10;
      addTearDown(() => native.free(pointer.cast()));
      final change = native
          .pointer()
          .asFunction<Pointer<Int64> Function(Pointer<Int64>, int)>();
      expect(change(pointer, 4), pointer);
      expect(pointer.value, 14);
      expect(change(pointer, -1), nullptr);
      final value = Struct.create<CallbackState>();
      value.count = 5;
      value.value = 1.25;
      value.entries[0] = 7;
      value.entries[1] = 9;
      final compound = native
          .compound()
          .asFunction<CallbackState Function(CallbackState, bool)>();
      final result = compound(value, false);
      expect((result.count, result.value, result.entries[1]), (6, 2.5, 16));
      expect((value.count, value.value, value.entries[1]), (5, 1.25, 9));
      final failed = compound(value, true);
      expect(
        (failed.count, failed.value, failed.entries[0], failed.entries[1]),
        (0, 0.0, 0, 0),
      );
    },
  );

  test(
    'callbacks reject a foreign OS thread before entering the managed heap',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/native_callbacks_thread.dart',
      ]);
      expect(result.exitCode, 70, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
