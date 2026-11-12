// FFI storage subclasses cannot declare generative constructors.
// ignore_for_file: use_primary_constructors

import 'dart:ffi';

import 'package:dartc/interop.dart';

final class Point extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class Mixed extends Struct {
  @Int32()
  external int tag;
  @Double()
  external double value;
}

final class Large extends Struct {
  @Int64()
  external int first;
  @Int64()
  external int second;
  @Int64()
  external int third;
}

final class Choice extends Union {
  @Uint64()
  external int bits;
  @Double()
  external double value;
}

@Export<Point Function(Point, Double)>()
Point translate(Point point, double distance) {
  point.x += distance;
  point.y -= distance;
  return point;
}

@Export<Mixed Function(Mixed, Int32)>()
Mixed changeMixed(Mixed data, int tag) {
  data.tag = tag;
  data.value *= 2;
  return data;
}

@Export<Large Function(Large, Int64)>()
Large changeLarge(Large data, int delta) {
  final result = Struct.create<Large>();
  result.first = data.third + delta;
  result.second = data.first;
  result.third = data.second;
  return result;
}

@Export<Choice Function(Choice)>()
Choice negateChoice(Choice data) {
  data.value = -data.value;
  return data;
}

@Export<Void Function(Pointer<Mixed>, Double)>()
void accumulate(Pointer<Mixed> state, double value) {
  state.ref.value += value;
  state.ref.tag++;
}

@Packed(1)
final class PackedValue extends Struct {
  @Uint8()
  external int tag;
  @Double()
  external double value;
}

final class Nested extends Struct {
  external Point point;
  @Bool()
  external bool enabled;
  @IntPtr()
  external int count;
}

@Export<PackedValue Function(PackedValue)>()
PackedValue packed(PackedValue data) {
  data.tag += 1;
  data.value += 0.5;
  return data;
}

@Export<Nested Function(Nested, Bool)>()
Nested nested(Nested data, bool enabled) {
  final view = data.point;
  for (var i = 0; i < 20000; i++) {
    Struct.create<Mixed>();
  }
  view.y += 2;
  data.enabled = enabled;
  data.count += sizeOf<Nested>();
  return data;
}

typedef PointTransform = Point Function(Point, Double);
typedef LargeTransform = Large Function(Large, Int64);

@Export<
  Point Function(Pointer<NativeFunction<PointTransform>>, Point, Double)
>()
Point applyPoint(
  Pointer<NativeFunction<PointTransform>> transform,
  Point point,
  double delta,
) => transform.asFunction<Point Function(Point, double)>()(point, delta);

@Export<Large Function(Pointer<NativeFunction<LargeTransform>>, Large, Int64)>()
Large applyLarge(
  Pointer<NativeFunction<LargeTransform>> transform,
  Large value,
  int delta,
) => transform.asFunction<Large Function(Large, int)>()(value, delta);

@Export<
  Point Function(
    Double,
    Double,
    Double,
    Double,
    Double,
    Double,
    Double,
    Point,
    Double,
  )
>()
Point stackPoint(
  double a,
  double b,
  double c,
  double d,
  double e,
  double f,
  double g,
  Point point,
  double last,
) {
  point.x += a + b + c + d + e + f + g;
  point.y += last;
  return point;
}
