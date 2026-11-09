import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Double Function(Double, Double)>()
double modulo(double left, double right) => left % right;
