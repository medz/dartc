import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/src/runtime/heap.dart';

@Export<Int64 Function(Int64, Int64)>()
int capacity(int current, int needed) => heapCapacity(current, needed);
