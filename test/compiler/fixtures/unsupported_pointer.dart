import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Pointer<Float> Function(Int64)>()
Pointer<Float> pointer(int address) => .fromAddress(address);
