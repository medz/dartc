import 'dart:ffi';

import 'package:dartc/interop.dart';

@AbiSpecificIntegerMapping({
  Abi.macosArm64: Int8(),
  Abi.macosX64: Int16(),
  Abi.linuxArm64: Uint16(),
  Abi.linuxX64: Int32(),
})
final class PlatformInt extends AbiSpecificInteger {
  // shortcut: analyzer's FFI verifier misses primary constructors; use one when fixed.
  // ignore: use_primary_constructors
  const new();
}

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
