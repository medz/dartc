import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'constant_safety/numeric.dart';

const annotation = equal ? Object() : Export<Int64 Function()>(symbol: 'right');

@annotation
int value() => 1;
