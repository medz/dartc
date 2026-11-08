import 'dart:ffi';

import 'package:dartc/export.dart' as native;

final class const Export<T extends Function>({final String? symbol});

typedef AddNative = Int64 Function(Int64, Int64);

@native.Export<AddNative>(symbol: 'bound_add')
int add(int a, int b) => a + b;

@Export<AddNative>(symbol: 'not_native')
int ordinary(int a, int b) => a - b;
