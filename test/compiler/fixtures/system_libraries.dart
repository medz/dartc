import 'dart:ffi';

import '../../../lib/runtime/contracts.dart';

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'sin', isLeaf: true)
external double sine(double value);

@SystemNative()
@Native<Int Function()>(symbol: 'getpid', isLeaf: true)
external int processId();

@SystemNative(library: .dynamicLoader)
@Native<Pointer<Uint8> Function()>(symbol: 'dlerror')
external Pointer<Uint8> loaderError();

@SystemNative(library: .math)
@Native<Double Function(Double)>(symbol: 'dartc_missing_unused_symbol')
external double unused(double value);

void main() {
  loaderError();
  final value = sine(0.5);
  if (processId() <= 0 || value < 0.4794 || value > 0.4795) {
    throw StateError('system library binding');
  }
  print('system_libraries:ok');
}
