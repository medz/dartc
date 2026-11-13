import 'dart:ffi';

import '../../../lib/runtime/contracts.dart';

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'sin', isLeaf: true)
external double sine(double value);

@SystemNative()
@Native<Int Function()>(symbol: 'getpid', isLeaf: true)
external int processId();

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'dartc_missing_unused_symbol')
external double unused(double value);

void main() {
  final value = sine(0.5);
  if (processId() <= 0 || value < 0.4794 || value > 0.4795) {
    throw StateError('system library binding');
  }
  print('system_libraries:ok');
}
