import 'dart:ffi';

import 'package:dartc/runtime/contracts.dart';

@NonAllocating()
@SystemNative(library: .math)
@Native<Int Function()>(symbol: 'getpid')
external int processId();

void main() {
  processId();
  DateTime.now();
}
