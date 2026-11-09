import 'dart:ffi';

import 'package:dartc/export.dart';

const rounded = 9007199254740993 == 9007199254740992.0;

@Export<Int64 Function()>()
int result() => rounded ? 1 : 0;
