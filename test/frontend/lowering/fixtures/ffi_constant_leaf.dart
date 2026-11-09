import 'dart:ffi';

typedef NativeUnary = Int64 Function(Int8);
typedef DartUnary = int Function(int);

DartUnary constantLeaf(int address) =>
    Pointer<NativeFunction<NativeUnary>>.fromAddress(address)
        .asFunction<DartUnary>(isLeaf: 1 + 1 == 2);
