import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64)>()
Pointer<Int64> pointer(int address) => .fromAddress(address);
