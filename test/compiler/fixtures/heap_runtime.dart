import 'dart:ffi';

import 'package:dartc/interop.dart';
import 'package:dartc/src/runtime/allocator.dart';

@Export<Int64 Function(Int64)>()
int capacity(int needed) => slotSize(needed);
