import 'dart:ffi';
import 'dart:io';

import 'native_callbacks_ffi.dart';

void main() {
  final native = NativeCallbacks();
  final callback = native.thread();
  final system = DynamicLibrary.process();
  final create = system
      .lookupFunction<
        Int32 Function(
          Pointer<UintPtr>,
          Pointer<Void>,
          Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<UintPtr>,
          Pointer<Void>,
          Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>,
          Pointer<Void>,
        )
      >('pthread_create');
  final join = system
      .lookupFunction<
        Int32 Function(UintPtr, Pointer<Pointer<Void>>),
        int Function(int, Pointer<Pointer<Void>>)
      >('pthread_join');
  final thread = native.allocate(sizeOf<UintPtr>()).cast<UintPtr>();
  if (thread == nullptr) exit(3);
  if (create(thread, nullptr, callback, nullptr) != 0) exit(2);
  join(thread.value, nullptr);
  native.free(thread.cast());
  native.close();
}
