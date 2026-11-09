import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Double Function(Double, Double)>()
double modulo(double left, double right) => left % right;
