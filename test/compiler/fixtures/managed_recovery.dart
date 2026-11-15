import 'dart:ffi';

import 'managed_objects.dart';

@Native<Int64 Function(Int64)>(assetId: 'heap-test', symbol: 'limit')
external int restrictMemory(int bytes);

void recover(bool initialized) {
  Allocation? head;
  if (initialized) head = Allocation(42, 0, null, .fromAddress(0));
  var count = 0;
  var cleaned = false, propagated = true;
  OutOfMemoryError? original;
  StackTrace? originalTrace;
  final limit = restrictMemory(0);
  try {
    try {
      for (; count < 1000000; count++) {
        head = Allocation(count, 0, head, .fromAddress(0));
      }
    } on OutOfMemoryError catch (error, trace) {
      propagated = false;
      original = error;
      originalTrace = trace;
      rethrow;
    } finally {
      cleaned = true;
    }
  } on OutOfMemoryError catch (error, trace) {
    propagated = identical(original, error) && identical(originalTrace, trace);
  } finally {
    restrictMemory(limit);
  }
  var intact = true;
  for (var i = count - 1; i >= 0; i--) {
    intact &= head?.value == i;
    head = head?.previous;
  }
  intact &= initialized ? head?.value == 42 : head == null;
  print('$cleaned:$propagated:$intact:${original?.stackTrace == null}');
}

void main() {
  recover(false);
  recover(true);
  recover(true);
}
