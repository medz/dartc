import 'dart:ffi';

import 'package:dartc/interop.dart';

int _count = 0;

class Counter(bool fail) {
  this {
    _count++;
    if (fail) throw _count;
  }
}

class Box<T>(final T value, super.fail) extends Counter;

@Export<Int64 Function(Int64, Bool)>()
int construct(int value, bool fail) {
  try {
    return Box<int>(value, fail).value;
  } catch (_) {
    return -_count;
  }
}

@Export<Void Function(Int64)>()
void remember(int value) => Box<int>(value, false);

@Export<Int64 Function()>()
int count() => _count;

int _recurse(int depth) {
  if (depth == 0) throw 7;
  if (depth == 1) return 11;
  return _recurse(depth - 2);
}

@Export<Int64 Function(Int64)>()
int recoverDepth(int depth) {
  try {
    return _recurse(depth);
  } catch (_) {
    return 7;
  }
}
