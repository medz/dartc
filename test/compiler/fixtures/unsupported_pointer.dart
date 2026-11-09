import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Pointer<Void> Function(Int64)>()
Pointer<Void> pointer(int address) => .fromAddress(address);
