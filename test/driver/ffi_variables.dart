// A program that uses variables of C, and those. It opens `LIBRARY`.

const variablesC = r'''
#include <stdint.h>
#include <stdbool.h>
typedef struct { int32_t x, y; } Point;
typedef union { int32_t i; float f; } Any;
int8_t v_i8 = -3;
uint8_t v_u8 = 200;
int16_t v_i16 = -300;
uint16_t v_u16 = 60000;
int32_t v_i32 = -5;
uint32_t v_u32 = 4000000000u;
int64_t v_i64 = -7;
float v_f = 1.5f;
double v_d = 2.25;
bool v_b = true;
int32_t *v_p = &v_i32;
Point v_point = {1, 2};
Any v_any = {3};
int32_t v_list[3] = {7, 8, 9};
int32_t v_grid[2][2] = {{1, 2}, {3, 4}};
Point v_points[2] = {{5, 6}, {7, 8}};
int32_t v_static = 11;
const int32_t v_const = 12;
long v_long = 13;
int32_t get_i32(void) { return v_i32; }
int32_t sum(void) { return v_point.x + v_point.y + v_list[0] + v_list[1]; }
''';

const variablesDart = r'''
import 'dart:convert';
import 'dart:ffi';

final class Point extends Struct {
  @Int32()
  external int x, y;
}

final class Any extends Union {
  @Int32()
  external int i;
  @Float()
  external double f;
}

@Native<Pointer<Void> Function(Pointer<Uint8>, Int32)>()
external Pointer<Void> dlopen(Pointer<Uint8> name, int flags);
@Native<Pointer<Uint8> Function(Size)>()
external Pointer<Uint8> malloc(int size);

@Native<Int8>()
external int v_i8;
@Native<Uint8>()
external int v_u8;
@Native<Int16>()
external int v_i16;
@Native<Uint16>()
external int v_u16;
@Native<Int32>()
external int v_i32;
@Native<Uint32>()
external int v_u32;
@Native<Int64>(symbol: 'v_i64')
external int renamed;
@Native<Float>()
external double v_f;
@Native<Double>()
external double v_d;
@Native<Bool>()
external bool v_b;
@Native<Pointer<Int32>>()
external Pointer<Int32> v_p;
@Native()
external Pointer<Int32> get v_q;
@Native<Point>()
external Point v_point;
@Native()
external Any v_any;
@Native<Array<Int32>>()
@Array(3)
external Array<Int32> v_list;
@Array(2, 2)
@Native()
external Array<Array<Int32>> v_grid;
@Array(2)
@Native()
external final Array<Point> v_points;
@Native<Long>()
external final int v_long;
@Native<Int32>()
external int v_missing;
@Native<Int32 Function()>()
external int get_i32();
@Native<Int32 Function()>(symbol: 'get_i32')
external int get viaFunction;
@Native<Int32 Function()>()
external int sum();

class A {
  @Native<Int32>()
  external static int v_static;
  @Native<Int32>()
  external static final int v_const;
}

void main() {
  final path = utf8.encode('LIBRARY');
  final name = malloc(path.length + 1);
  name.asTypedList(path.length + 1)
    ..setAll(0, path)
    ..[path.length] = 0;
  print(dlopen(name, 0x10a) != nullptr);
  print((v_i8, v_u8, v_i16, v_u16, v_i32, v_u32, renamed, v_long));
  v_i8 = 300;
  v_u8 = 300;
  v_i16 = 70000;
  v_u16 = 70000;
  v_i32 = 1 << 33 | 6;
  v_u32 = -1;
  renamed = -1;
  print((v_i8, v_u8, v_i16, v_u16, v_i32, v_u32, renamed));
  print((v_f, v_d, v_b));
  v_f = 0.1;
  v_d = 0.1;
  v_b = false;
  print((v_f, v_d, v_b));
  v_b = !v_b;
  print(v_b);
  v_i32 += 2;
  print(v_i32++);
  print(--v_i32);
  print(get_i32());
  print(viaFunction);
  print(v_p.value);
  print(v_p == Native.addressOf<Int32>(v_i32));
  v_p = Native.addressOf<Int32>(v_u32).cast();
  print(v_p.value);
  v_p = nullptr;
  print(v_p);
  print((v_point.x, v_point.y, v_point.runtimeType));
  v_point.x = 20;
  final other = Struct.create<Point>()
    ..x = 30
    ..y = 40;
  print((v_point.x, v_point.y, sum()));
  v_point = other;
  other.x = 50;
  print((v_point.x, v_point.y, sum()));
  print((v_any.i, v_any.f));
  v_any.f = 1.0;
  print(v_any.i);
  v_any = Union.create<Any>()..i = 8;
  print(v_any.i);
  print([for (var i = 0; i < 3; i++) v_list[i]]);
  v_list[1] = 80;
  print(v_list.elements);
  print(sum());
  try {
    v_list[3];
  } catch (e) {
    print(e.runtimeType);
  }
  print((v_grid[0][1], v_grid[1][0], v_grid.runtimeType));
  v_grid[1][0] = 33;
  print(v_grid[1].elements);
  print((v_points[0].x, v_points[1].y));
  v_points[1].y = 88;
  print(v_points[1].y);
  print((A.v_static, A.v_const));
  A.v_static = 111;
  print(A.v_static);
  print(Native.addressOf<Int32>(A.v_static).value);
  print(Native.addressOf<Point>(v_point).ref.x);
  print(Native.addressOf<Array<Int32>>(v_list).cast<Int32>()[1]);
  print(Native.addressOf<Pointer<Int32>>(v_p).value);
  print(Native.addressOf<Double>(v_d).value);
  for (final use in [
    () => v_missing,
    () => v_missing = 1,
    () => Native.addressOf<Int32>(v_missing),
  ]) {
    try {
      print(use());
    } catch (e) {
      print('$e'.split("'")[1]);
    }
  }
  final read = () => v_i32;
  print(read());
  int? n;
  v_i32 = n ?? 4;
  print(v_i32);
  final List<int> l = [v_i32, ...v_list.elements];
  print(l);
}
''';
