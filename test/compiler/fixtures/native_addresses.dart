@DefaultAsset('borrowed-addresses')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/interop.dart';

@Native<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UintPtr)>(
  symbol: 'memmove',
  isLeaf: true,
)
external Pointer<Void> move(
  Pointer<Void> target,
  Pointer<Void> source,
  int bytes,
);

@Export<Int64 Function(Int32)>()
int integerLists(int kind) {
  switch (kind) {
    case 0:
      final data = Int8List.fromList([-7, 0]);
      move(data[1].address.cast(), data.address.cast(), 1);
      return data[1];
    case 1:
      final data = Uint8List.fromList([251, 0]);
      move(data[1].address.cast(), data.address.cast(), 1);
      return data[1];
    case 2:
      final data = Int16List.fromList([-31999, 0]);
      move(data[1].address.cast(), data.address.cast(), 2);
      return data[1];
    case 3:
      final data = Uint16List.fromList([65000, 0]);
      move(data[1].address.cast(), data.address.cast(), 2);
      return data[1];
    case 4:
      final data = Int32List.fromList([-2000000000, 0]);
      move(data[1].address.cast(), data.address.cast(), 4);
      return data[1];
    case 5:
      final data = Uint32List.fromList([4000000000, 0]);
      move(data[1].address.cast(), data.address.cast(), 4);
      return data[1];
    case 6:
      final data = Int64List.fromList([-0x123456789abcdef, 0]);
      copyInteger(data);
      return data[1];
    default:
      final data = Uint64List.fromList([0x123456789abcdef, 0]);
      move(data[1].address.cast(), data.address.cast(), 8);
      return data[1];
  }
}

void copyInteger<T extends Int64List>(T data) {
  Int64List target = data;
  move(target[1].address.cast(), data.address.cast(), 8);
}

@Export<Double Function(Bool)>()
double floatingLists(bool single) {
  if (single) {
    final data = Float32List.fromList([-1.25, 0]);
    move(data[1].address.cast(), data.address.cast(), 4);
    return data[1];
  }
  final data = Float64List.fromList([1.125, 0]);
  move(data[1].address.cast(), data.address.cast(), 8);
  return data[1];
}

// FFI storage subclasses cannot declare generative constructors.
// ignore: use_primary_constructors
final class AddressState extends Struct {
  @Int64()
  external int count;
  @Double()
  external double value;
  @Bool()
  external bool enabled;
  @Array(3)
  external Array<Int32> entries;
}

// ignore: use_primary_constructors
final class AddressChoice extends Union {
  @Double()
  external double value;
  @Uint64()
  external int bits;
}

@Export<AddressState Function()>()
AddressState compounds() {
  final state = Struct.create<AddressState>();
  move(
    state.count.address.cast(),
    Int64List.fromList([-321]).address.cast(),
    8,
  );
  move(
    state.value.address.cast(),
    Float64List.fromList([1.25]).address.cast(),
    8,
  );
  move(state.enabled.address.cast(), Uint8List.fromList([1]).address.cast(), 1);
  move(
    state.entries.address.cast(),
    Int32List.fromList([11, 22, 33]).address.cast(),
    12,
  );
  move(state.entries[1].address.cast(), state.entries[2].address.cast(), 4);
  final copy = Struct.create<AddressState>();
  copyState(copy, state);
  final choice = Union.create<AddressChoice>();
  move(choice.address.cast(), Float64List.fromList([2.5]).address.cast(), 8);
  move(copy.value.address.cast(), choice.value.address.cast(), 8);
  return copy;
}

void copyState<T extends AddressState>(T target, T source) =>
    move(target.address.cast(), source.address.cast(), sizeOf<AddressState>());

@Export<Bool Function()>()
bool subviews() {
  final data = Uint8List.fromList([1, 2, 3, 4, 5]);
  final view = Uint8List.sublistView(data, 1, 4);
  final result = move(view.address.cast(), view[1].address.cast(), 2);
  return data[0] == 1 &&
      data[1] == 3 &&
      data[2] == 4 &&
      data[3] == 4 &&
      result.address != 0;
}

int _trace = 0;

Uint8List source() {
  _trace = _trace * 10 + 1;
  return .fromList([9, 8]);
}

int later(bool fail) {
  _trace = _trace * 10 + 2;
  for (var i = 0; i < 40000; i++) {
    final garbage = Uint8List.fromList([i]);
    if (garbage[0] == 256) throw StateError('unreachable');
  }
  if (fail) throw StateError('later argument');
  return 2;
}

@Export<Int64 Function(Pointer<Uint8>, Bool)>()
int ordered(Pointer<Uint8> output, bool fail) {
  _trace = 0;
  try {
    move(output.cast(), source().address.cast(), later(fail));
  } on StateError {
    _trace = _trace * 10 + 3;
  }
  return _trace;
}
