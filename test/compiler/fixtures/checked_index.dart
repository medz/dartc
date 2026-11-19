import 'dart:ffi';

import 'package:dartc/interop.dart';

int checks = 0;

void checkIndex(int index) {
  checks++;
  if (index < 0) throw 73;
}

@Export<Int64 Function(Int64, Bool)>()
int checkedIndex(int index, bool enforce) {
  checks = 0;
  if (enforce) {
    try {
      checkIndex(index);
      if (index < 0) return 701;
    } catch (error) {
      return identical(error, 73) && index < 0 ? 80 + checks : 99;
    }
  }
  return index + checks;
}
