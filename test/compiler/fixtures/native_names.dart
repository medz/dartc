// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors
import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'native_names_other.dart' as other;

final class Point extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class State extends Struct {
  @Int64()
  external int _value;
  @Int32()
  external int register;

  int get value => _value;
}

@Export<Point Function(Point, other.Point)>()
Point combine(Point first, other.Point second) {
  first.x += second.value;
  first.y *= second.value;
  return first;
}

@Export<State Function(Int64)>()
State makeState(int value) => Struct.create<State>()
  .._value = value
  ..register = 17;

typedef ConvertPoint = other.Point Function(Point);

@Export<other.Point Function(Pointer<NativeFunction<ConvertPoint>>, Point)>()
other.Point convertPoint(
  Pointer<NativeFunction<ConvertPoint>> callback,
  Point value,
) => callback.asFunction<other.Point Function(Point)>()(value);
