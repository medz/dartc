import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Pointer<Int8> Function(Int64)>()
Pointer<Int8> pointer(int address) => .fromAddress(address);
