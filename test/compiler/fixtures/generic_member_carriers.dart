import 'dart:ffi';

import 'package:dartc/interop.dart';

class Selector<T> {
  const Selector();

  T select(T first, T next, int depth) =>
      depth <= 0 ? first : select(next, first, depth - 1);
}

// The receiver type varies independently from the integer data. In both cases
// recursion must preserve the selected value and the declared method identity.
@Export<Int64 Function(Int64, Int64, Int64, Int64)>()
int selectWord(int mode, int first, int next, int depth) {
  final Selector<num> receiver =
      mode == 0 ? const Selector<int>() : const Selector<num>();
  return receiver.select(first, next, depth) as int;
}
