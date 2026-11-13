import 'dart:collection';
import 'dart:ffi';

import 'package:dartc/interop.dart';

@AbiSpecificIntegerMapping({
  Abi.macosArm64: Int8(),
  Abi.macosX64: Int16(),
  Abi.linuxArm64: Uint16(),
  Abi.linuxX64: Int32(),
})
// shortcut: analyzer 14.7 omits primary FFI constructors, remove this suppression when its verifier is fixed.
// ignore: abi_specific_integer_invalid
final class const PlatformInt() extends AbiSpecificInteger;

final class IntegerState() extends Struct {
  @Uint8()
  external int prefix;

  @PlatformInt()
  external int value;

  @Array(3)
  external Array<PlatformInt> values;

  @Uint8()
  external int suffix;
}

@Export<PlatformInt Function(PlatformInt)>()
int identity(int value) => value;

@Export<Char Function(Char)>()
int character(int value) => value;

@Export<Size Function()>()
int integerSize() => sizeOf<PlatformInt>();

@Export<Size Function()>()
int stateSize() => sizeOf<IntegerState>();

@Export<PlatformInt Function(Pointer<PlatformInt>, IntPtr, Int64)>()
int access(Pointer<PlatformInt> values, int index, int value) {
  values[index] = value;
  return (values + index).value;
}

@Export<Pointer<PlatformInt> Function(Pointer<PlatformInt>, IntPtr)>()
Pointer<PlatformInt> offset(Pointer<PlatformInt> values, int index) =>
    values - index;

@Export<Int64 Function(Pointer<IntegerState>, Int64)>()
int update(Pointer<IntegerState> state, int value) {
  state.ref.value = value;
  state.ref.values[1] = value + 1;
  return state.ref.value + state.ref.values[1];
}

@Export<Int64 Function(Pointer<IntegerState>, Int64)>()
int arrayList(Pointer<IntegerState> state, int value) {
  final list = state.ref.values.elements;
  final readonly = UnmodifiableListView(list);
  list[0] = value;
  state.ref.values[1] = value + 1;
  list[2] = readonly[0] + readonly[1];
  list.setRange(1, 3, list);
  return list.fold(0, (sum, value) => sum + value);
}

@Export<Bool Function(Pointer<IntegerState>, Int32)>()
bool arrayListFailure(Pointer<IntegerState> state, int mode) {
  final list = state.ref.values.elements;
  try {
    switch (mode) {
      case 0:
        list[-1];
      case 1:
        list[3] = 0;
      case 2:
        list.length = list.length;
      case 3:
        list.add(0);
      case 4:
        list.clear();
      case 5:
        UnmodifiableListView(list)[0] = 0;
    }
  } on RangeError {
    return mode < 2;
  } on UnsupportedError {
    return mode >= 2;
  }
  return false;
}

List<int>? _retained;

@Export<Void Function(Int64)>()
void retainArrayList(int value) {
  final state = Struct.create<IntegerState>();
  state.values[0] = value;
  _retained = state.values.elements;
}

@Export<Int64 Function(Int32)>()
int readRetainedArrayList(int count) {
  for (var i = 0; i < count; i++) {
    Struct.create<IntegerState>().value = i;
  }
  final list = _retained!;
  list[1] = list[0];
  return list[1];
}

typedef Callback = PlatformInt Function(PlatformInt);

@Export<Int64 Function(Pointer<NativeFunction<Callback>>, Int64)>()
int invoke(Pointer<NativeFunction<Callback>> callback, int value) =>
    callback.asFunction<int Function(int)>()(value);

@Export<
  PlatformInt Function(
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
    PlatformInt,
  )
>()
int stack(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  int j,
) => a + b + c + d + e + f + g + h + i + j;
