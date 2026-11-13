import 'managed_failure.dart' show restrictMemory;
import 'managed_objects.dart';

void recover(bool initialized) {
  Allocation? head;
  if (initialized) head = Allocation(42, 0, null, .fromAddress(0));
  var count = 0;
  var cleaned = false, caught = false, propagated = false;
  OutOfMemoryError? original;
  StackTrace? originalTrace;
  final limit = restrictMemory(0);
  try {
    try {
      for (; count < 1000000; count++) {
        head = Allocation(count, 0, head, .fromAddress(0));
      }
    } on OutOfMemoryError catch (error, trace) {
      caught = true;
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
  // Force fresh pages and collection before checking the surviving chain.
  allocateAndNotify(10000, 0, .fromAddress(0));
  var intact = true;
  for (var i = count - 1; i >= 0; i--) {
    intact &= head?.value == i;
    head = head?.previous;
  }
  intact &= initialized ? head?.value == 42 : head == null;
  print('$caught:$cleaned:$propagated:$intact:${original?.stackTrace == null}');
}

int number(int value) => value + 1;
Object object(Object value) => value;

bool recoverBoxing(int mode) {
  Object? value;
  var caught = false;
  final limit = restrictMemory(0);
  try {
    if (mode == 0) {
      value = number(41) as Object;
    } else if (mode == 1) {
      value = object(number(41));
    } else {
      value = (number(41), number(42));
    }
  } on OutOfMemoryError {
    caught = true;
  } finally {
    restrictMemory(limit);
  }
  return caught && value == null;
}

bool recoverType<T>() {
  Type? value;
  var caught = false;
  final limit = restrictMemory(0);
  try {
    value = List<T>;
  } on OutOfMemoryError {
    caught = true;
  } finally {
    restrictMemory(limit);
  }
  return caught && value == null;
}

bool recoverTypeTest<T>(Object value) {
  var caught = false;
  final limit = restrictMemory(0);
  try {
    if (value is List<T>) return false;
  } on OutOfMemoryError {
    caught = true;
  } finally {
    restrictMemory(limit);
  }
  return caught;
}

Object boxedResult() {
  try {
    return number(41);
  } on OutOfMemoryError {
    return false;
  }
}

bool recoverReturn() {
  final limit = restrictMemory(0);
  try {
    return identical(boxedResult(), false);
  } finally {
    restrictMemory(limit);
  }
}

void main() {
  final cast = recoverBoxing(0);
  final implicit = recoverBoxing(1);
  final record = recoverBoxing(2);
  final type = recoverType<int>();
  final typeTest = recoverTypeTest<int>('value');
  final returned = recoverReturn();
  recover(false);
  print('$cast:$implicit:$record:$type:$typeTest:$returned');
  recover(true);
  recover(true);
}
