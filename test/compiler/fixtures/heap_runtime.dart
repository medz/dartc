import 'dart:ffi';

import 'package:dartc/interop.dart';

import '../../../sdk/runtime/allocator.dart';

@Export<Int64 Function(Int64)>()
int capacity(int needed) => slotSize(needed);
