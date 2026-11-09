import 'dart:ffi';

import 'package:dartc/interop.dart';

@Native<Pointer<Int64> Function()>(assetId: 'test:io', symbol: 'state')
external Pointer<Int64> _state();

@Export<Int64 Function(Int32, Pointer<Uint8>, Uint64)>(symbol: 'test_write')
int write(int descriptor, Pointer<Uint8> bytes, int count) {
  final state = _state();
  state[0] += 1;
  state[3] = descriptor;
  state[4] = bytes.address;
  state[5] = count;
  if (state[0] <= state[2]) {
    state[6] = 4;
    return -1;
  }
  state[6] = state[7];
  return state[1];
}

@Export<Pointer<Int32> Function()>(symbol: 'test_errno')
Pointer<Int32> errno() => Pointer<Int32>.fromAddress(_state().address + 48);
