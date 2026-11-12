import 'dart:ffi';

@Native<Pointer<NativeFinalizerFunction> Function()>(assetId: 'finalizer-test')
external Pointer<NativeFinalizerFunction> callback();

final class Resource() implements Finalizable;

Resource? retained;

void main() {
  retained = Resource();
  NativeFinalizer(callback()).attach(retained!, nullptr);
}
