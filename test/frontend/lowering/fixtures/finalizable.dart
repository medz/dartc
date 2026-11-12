import 'dart:ffi';

final class Resource(final Pointer<Void> address) implements Finalizable;

external void consume(Pointer<Void> address);

void forever(Resource resource) {
  final address = resource.address;
  for (;;) {
    consume(address);
  }
}
