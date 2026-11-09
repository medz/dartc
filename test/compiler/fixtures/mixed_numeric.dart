import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Int64 Function(Int64, Double)>()
int compare(int integer, double floating) => integer == floating ? 1 : 0;
