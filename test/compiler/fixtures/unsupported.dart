import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64)>()
int divide(int left, int right) => left ~/ right;
