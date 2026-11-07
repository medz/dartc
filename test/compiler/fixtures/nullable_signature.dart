import 'dart:ffi';

import 'package:dartc/export.dart';

typedef NullableSignature = Int64 Function()?;

@Export<NullableSignature>()
int value() => 42;
