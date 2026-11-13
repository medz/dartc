// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors

import 'dart:ffi';

final class Pair extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class Triple extends Struct {
  @Int64()
  external int a;
  @Int64()
  external int b;
  @Int64()
  external int c;
}

typedef AggregateCallback = Double Function(Int, VarArgs<(Pair, Triple)>);
typedef DartAggregateCallback = double Function(int, Pair, Triple);
