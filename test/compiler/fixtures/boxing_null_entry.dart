import 'dart:ffi';

import 'numeric_boxes.dart';

@Native<Void Function()>(assetId: 'heap-test', symbol: 'limit')
external void restrictMemory();

void main() {
  restrictMemory();
  optional(42, 0);
}
