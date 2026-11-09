import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Pointer<Int64>)>()
int address(Pointer<Int64>? pointer) => pointer?.address ?? 0;
