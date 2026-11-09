import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64)>()
int checked(int value) {
  if (value < 0) throw value;
  return value;
}
