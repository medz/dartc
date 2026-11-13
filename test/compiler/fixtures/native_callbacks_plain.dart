import 'dart:ffi';

import 'package:dartc/interop.dart';

abstract final class Callbacks() {
  static double floating(double value) {
    if (value < 0) throw StateError('negative');
    return value / 2;
  }
}

@Export<Pointer<NativeFunction<Float Function(Float)>> Function()>()
Pointer<NativeFunction<Float Function(Float)>> plainCallback() =>
    Pointer.fromFunction<Float Function(Float)>(Callbacks.floating, -2.5);
