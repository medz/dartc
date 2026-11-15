import 'dart:ffi';

import 'package:dartc/runtime/contracts.dart';

@NonAllocating()
@SystemNative(library: .math)
@Native<Int Function()>(symbol: 'getpid')
external int processId();

@RuntimeEntry(.recordError)
void untrustedDefinition(Object error, StackTrace trace) {}

@RuntimeEntry(.recordError)
external void untrustedReference(Object error, StackTrace trace);

void main() {
  processId();
  DateTime.now();
}
