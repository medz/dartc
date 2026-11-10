import 'dart:ffi';

import 'managed_objects.dart';

@Native<Void Function()>(assetId: 'heap-test', symbol: 'limit')
external void restrictMemory();

void exhaust(bool initialize) {
  Allocation? previous;
  if (initialize) previous = Allocation(0, 0, null, .fromAddress(0));
  restrictMemory();
  for (var i = 0; i < 10000; i++) {
    previous = Allocation(i, 0, previous, .fromAddress(0));
  }
}

void main() => exhaust(false);
