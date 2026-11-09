import 'dart:ffi';

@Native<Pointer<Int64> Function()>(assetId: 'entry', symbol: 'constant')
external Pointer<Int64> constant();

@Native<Pointer<Int64> Function()>(assetId: 'entry', symbol: 'state')
external Pointer<Int64> state();

@Native<Pointer<Int64> Function()>(assetId: 'entry', symbol: 'zero')
external Pointer<Int64> zero();

@Native<Void Function(Int32)>(assetId: 'entry', symbol: 'finish')
external void finish(int status);

void main() {
  final source = constant(), writable = state(), uninitialized = zero();
  uninitialized.value += source.value + writable.value;
  writable.value = uninitialized.value + 3;
  finish(writable.value);
}
