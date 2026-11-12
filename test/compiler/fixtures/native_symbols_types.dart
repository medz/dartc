import 'dart:ffi';

// FFI aggregate subclasses cannot declare generative constructors.
// ignore: use_primary_constructors
final class NativePair extends Struct {
  @Int64()
  external int integer;
  @Double()
  external double real;
}
