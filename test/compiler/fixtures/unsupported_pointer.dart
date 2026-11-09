import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Pointer<IntPtr> Function(Int64)>()
Pointer<IntPtr> pointer(int address) => .fromAddress(address);
