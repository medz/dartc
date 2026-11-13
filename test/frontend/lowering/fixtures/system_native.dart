import 'dart:ffi';

import 'package:dartc/runtime/contracts.dart';

@SystemNative(library: .math)
@Native<Int Function()>(symbol: 'getpid')
external int processId();

void main() {
  processId();
  DateTime.now();
}
