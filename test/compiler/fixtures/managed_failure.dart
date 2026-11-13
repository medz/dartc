import 'dart:ffi';

import 'managed_objects.dart';

@Native<Int64 Function(Int64)>(assetId: 'heap-test', symbol: 'limit')
external int restrictMemory(int bytes);

void exhaust(bool initialize) {
  Allocation? previous;
  if (initialize) previous = Allocation(0, 0, null, .fromAddress(0));
  restrictMemory(0);
  for (var i = 0; i < 10000; i++) {
    previous = Allocation(i, 0, previous, .fromAddress(0));
  }
}

void main() => exhaust(false);
