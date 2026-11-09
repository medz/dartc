import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'constant_safety/numeric.dart' as numbers;

@Export<Int64 Function()>(
  symbol: numbers.equal || !numbers.Compared.greater ? 'wrong' : 'right',
)
int value() => 1;
