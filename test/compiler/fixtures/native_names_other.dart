// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors
import 'dart:ffi';

final class Point extends Struct {
  @Int32()
  external int value;
}
