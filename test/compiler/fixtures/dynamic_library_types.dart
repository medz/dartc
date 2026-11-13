import 'dart:ffi';

final class LibraryValue() extends Struct {
  @Int32()
  external int tag;
  @Double()
  external double value;
}
