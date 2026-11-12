import 'dart:ffi';

@Native<Void Function(Pointer<Void>)>(assetId: 'finalizer-test')
external void finish(Pointer<Void> token);

final class Resource() implements Finalizable;

Resource? retained;

void main() {
  retained = Resource();
  NativeFinalizer(Native.addressOf(finish)).attach(retained!, nullptr);
}
