import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'dynamic_library_types.dart';

@Export<Double Function(Double, Double)>()
double blend(double a, double b) => a + b * 2;

@Export<Pointer<Double> Function(Pointer<Double>)>()
Pointer<Double> identity(Pointer<Double> value) => value;

@Export<LibraryValue Function(LibraryValue, Bool)>()
LibraryValue transform(LibraryValue input, bool negate) {
  input.tag += 7;
  input.value *= negate ? -2 : 2;
  return input;
}

@Export<
  Double Function(Pointer<NativeFunction<Double Function(Double)>>, Double)
>()
double invoke(
  Pointer<NativeFunction<Double Function(Double)>> callback,
  double value,
) => callback.asFunction<double Function(double)>()(value) + 0.5;
