@defaultAsset
library;

import 'dart:ffi' as ffi;

part 'native_imports_part.dart';

const defaultAsset = ffi.DefaultAsset('package:fixture/default');
typedef NativeUnary = ffi.Int64 Function(ffi.Int8);
const alias = ffi.Native<NativeUnary>(symbol: 'aliased', isLeaf: 1 + 1 == 2);

@alias
external int aliased(int value);

@ffi.Native<NativeUnary>(assetId: 'other', symbol: 'step')
external int redirected(int value);

@ffi.Native()
external ffi.Pointer<ffi.Int64> inferred(ffi.Pointer<ffi.Int64> value);

@ffi.Native()
external void release(ffi.Pointer<ffi.Void> value);

@ffi.Native<ffi.Pointer<ffi.Int64> Function(ffi.Pointer<ffi.Int64>)>()
external ffi.Pointer<ffi.NativeType> widened(ffi.Pointer<ffi.Int64> value);

class Api() {
  @ffi.Native<NativeUnary>()
  external static int staticCall(int value);
}

final class const Native<T>({final String? symbol});

@Native<NativeUnary>(symbol: 'ignored')
int ordinary(int value) => value;
