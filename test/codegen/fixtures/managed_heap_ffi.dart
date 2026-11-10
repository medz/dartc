import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

typedef HeapCallback = Void Function(Int64);

final class ManagedHeap() {
  final _library = NativeAssets(Target.host()).open('codegen/managed_heap');
  late final chain = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('heap_chain');
  late final cycles = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('heap_cycles');
  late final nested = _library
      .lookupFunction<
        Int64 Function(
          Int8,
          Int8,
          Int8,
          Int8,
          Int8,
          Int8,
          Int8,
          Int8,
          Int8,
          Int64,
        ),
        int Function(int, int, int, int, int, int, int, int, int, int)
      >('heap_nested');
  late final reenter = _library
      .lookupFunction<
        Int64 Function(Pointer<NativeFunction<HeapCallback>>, Int64),
        int Function(Pointer<NativeFunction<HeapCallback>>, int)
      >('heap_reenter');

  late final readState = _library
      .lookupFunction<Int64 Function(), int Function()>('heap_read_state');
  late final writeState = _library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'heap_write_state',
      );
  late final globalReenter = _library
      .lookupFunction<
        Int64 Function(Pointer<NativeFunction<HeapCallback>>, Int64),
        int Function(Pointer<NativeFunction<HeapCallback>>, int)
      >('heap_global_reenter');

  void close() => _library.close();
}
