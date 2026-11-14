// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors
import 'dart:ffi';

import 'package:dartc/interop.dart';

final class Oversized extends Struct {
  @Array((1 << 61) + 1)
  external Array<Double> values;
}

@Export<Int64 Function()>()
int nativeSize() => sizeOf<Oversized>();
