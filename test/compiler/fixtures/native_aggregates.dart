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

final class Arrays extends Struct {
  @Array(3)
  external Array<Int16> integers;
  @Array(2, 3)
  external Array<Array<Double>> matrix;
  @Array(2)
  external Array<Point> points;
  @Array(2)
  external Array<Pointer<Int64>> pointers;
  @Array(3)
  external Array<Bool> flags;
  @Array(4)
  external Array<Int16> longer;
}

@Export<Arrays Function(Arrays, Int32)>()
Arrays updateArrays(Arrays value, int index) {
  final row = value.matrix[1];
  final point = value.points[1];
  for (var i = 0; i < 20000; i++) {
    Struct.create<Point>();
  }
  row[index] += 0.5;
  value.matrix[0] = row;
  value.integers[index] += 32768;
  point.x += row[index];
  value.flags[index] = !value.flags[index];
  value.pointers[1] = value.pointers[0];
  return value;
}

@Export<Int32 Function(Arrays, Int32)>()
int arrayBounds(Arrays value, int index) {
  try {
    value.integers[index] = 17;
    return value.integers[index];
  } on RangeError {
    return -1;
  }
}

@Export<Arrays Function(Arrays, Arrays)>()
Arrays copyArrays(Arrays destination, Arrays source) {
  destination.integers = source.integers;
  destination.matrix = source.matrix;
  source.integers[0] = 99;
  return destination;
}

@Export<Arrays Function(Arrays)>()
Arrays copyArrayPrefix(Arrays value) {
  value.integers = value.longer;
  return value;
}
