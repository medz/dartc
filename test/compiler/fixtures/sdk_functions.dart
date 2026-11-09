import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64)>()
int nonnegative(int value) => RangeError.checkNotNegative(value);
