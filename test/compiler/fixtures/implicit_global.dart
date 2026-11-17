import 'dart:ffi';

import 'package:dartc/interop.dart';

bool? retained;

@Export<Void Function(Int64)>()
void writeRetained(int input) {
  retained = input < 0 ? null : input != 0;
}

@Export<Int64 Function()>()
int readRetained() {
  final value = retained;
  return value == null ? -1 : (value ? 1 : 0);
}
