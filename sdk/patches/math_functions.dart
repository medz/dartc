import 'dart:ffi';

import '../../lib/runtime/contracts.dart';

@SystemNative(library: .math)
@Native<Double Function(Double, Double)>(symbol: 'pow', isLeaf: true)
external double pow(double x, double y);

@SystemNative(library: .math)
@Native<Double Function(Double, Double)>(symbol: 'atan2', isLeaf: true)
external double atan2(double x, double y);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'sin', isLeaf: true)
external double sin(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'cos', isLeaf: true)
external double cos(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'tan', isLeaf: true)
external double tan(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'asin', isLeaf: true)
external double asin(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'acos', isLeaf: true)
external double acos(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'atan', isLeaf: true)
external double atan(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'exp', isLeaf: true)
external double exp(double x);

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'log', isLeaf: true)
external double log(double x);
