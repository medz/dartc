import 'dart:ffi';

import 'package:dartc/runtime/contracts.dart';

@SystemNative()
@Native<Int Function()>(symbol: 'getpid')
external int processId();

void main() => processId();
