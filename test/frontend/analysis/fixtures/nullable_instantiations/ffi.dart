import 'dart:ffi';

void unused(Pointer<NativeFunction<Int32 Function(Int32)>>? pointer) {
  pointer?.asFunction<int Function(int)>;
}
