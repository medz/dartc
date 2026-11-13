import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Double Function(Double, VarArgs<(Double,)>)>(symbol: 'variadic_sum')
double sum(double first, double second) => first + second;
