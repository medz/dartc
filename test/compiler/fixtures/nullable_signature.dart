import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef NullableSignature = Int64 Function()?;

@Export<NullableSignature>()
int value() => 42;
