import 'dart:ffi';

import 'package:dartc/export.dart';

import 'constant_safety/numeric.dart';

@Export<Int64 Function()>(symbol: unsafeEqual ? 'wrong' : 'right')
int value() => 1;
