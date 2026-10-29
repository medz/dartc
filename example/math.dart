import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Int64 Function(Int64, Int64)>()
int add(int a, int b) => a + b;

@Export<Int64>()
const int answer = 42;
