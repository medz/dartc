import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Int64 Function(Int64)>()
int add(int left, int right) => left + right;
