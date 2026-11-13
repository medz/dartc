// ignore_for_file: use_primary_constructors
import 'dart:ffi';

final class Invalid extends Struct {
  @Array.variable()
  external Array<Int32> values;

  @Int32()
  external int after;
}

void main() {}
