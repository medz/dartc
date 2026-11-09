import 'dart:ffi';

import 'package:dartc/export.dart';

import 'constant_safety/numeric.dart';

const annotation = unsafeEqual
    ? Object()
    : Export<Int64 Function()>(symbol: 'right');

@annotation
int value() => 1;
