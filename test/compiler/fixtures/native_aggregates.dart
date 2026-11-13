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
  external Array<Choice> choices;
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

@Export<Arrays Function(Arrays)>()
Arrays updateArrayViews(Arrays value) {
  final flags = value.flags.elements;
  final pointers = value.pointers.elements;
  final points = value.points.elements;
  final choices = value.choices.elements;
  final rows = value.matrix.elements;
  flags.fillRange(0, flags.length, true);
  flags[1] = false;
  pointers[1] = pointers[0];
  points[1].x += rows[1][1];
  choices[0].value = points[1].x;
  rows[0] = rows[1];
  rows[1][1] += 1;
  return value;
}

@Export<Bool Function(Arrays, Int32)>()
bool arrayViewFailure(Arrays value, int mode) {
  try {
    switch (mode) {
      case 0:
        value.flags.elements[-1];
      case 1:
        value.pointers.elements[2];
      case 2:
        value.points.elements[-1];
      case 3:
        value.choices.elements[2];
      case 4:
        value.matrix.elements[2];
      case 5:
        value.flags.elements.add(false);
      case 6:
        value.pointers.elements.length = 2;
      case 7:
        value.points.elements[0] = value.points[1];
      case 8:
        value.choices.elements[0] = value.choices[1];
      case 9:
        value.matrix.elements.add(value.matrix[0]);
      case 10:
        value.points.elements.setRange(0, 0, const <Point>[]);
    }
  } on RangeError {
    return mode < 5;
  } on UnsupportedError {
    return mode >= 5;
  }
  return false;
}

Point? _escapedPoint;
Choice? _escapedChoice;
Array<Double>? _escapedRow;
List<Pointer<Int64>>? _escapedPointers;
List<bool>? _escapedFlags;

@Export<Void Function(Double)>()
void retainArrayViews(double value) {
  final state = Struct.create<Arrays>();
  state.points[1].x = value;
  state.choices[1].value = value + 1;
  state.matrix[1][0] = value + 2;
  state.pointers[0] = Pointer<Int64>.fromAddress(0x1234);
  state.flags[0] = true;
  _escapedPoint = state.points.elements[1];
  _escapedChoice = state.choices.elements[1];
  _escapedRow = state.matrix.elements[1];
  _escapedPointers = state.pointers.elements;
  _escapedFlags = state.flags.elements;
}

@Export<Arrays Function(Int32)>()
Arrays readArrayViews(int count) {
  for (var i = 0; i < count; i++) {
    Struct.create<Arrays>().integers[0] = i;
  }
  final result = Struct.create<Arrays>();
  result.points[0].x = _escapedPoint!.x;
  result.choices[0].value = _escapedChoice!.value;
  result.matrix[0][0] = _escapedRow![0];
  result.pointers[0] = _escapedPointers![0];
  result.flags[0] = _escapedFlags![0];
  return result;
}
