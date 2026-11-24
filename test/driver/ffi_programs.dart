// Programs that use functions of C, and those. They open `LIBRARY`.

const numbersC = r'''
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
int32_t add(int32_t a, int32_t b) { return a + b; }
int8_t neg8(int8_t a) { return -a; }
uint8_t inc8(uint8_t a) { return a + 1; }
int16_t neg16(int16_t a) { return -a; }
uint16_t inc16(uint16_t a) { return a + 1; }
uint32_t inc32(uint32_t a) { return a + 1; }
int64_t add64(int64_t a, int64_t b) { return a + b; }
bool flip(bool b) { return !b; }
float halff(float f) { return f / 2; }
double mix(int8_t a, float b, double c, int64_t d, bool e, uint16_t f) { return a + b + c + d + e + f; }
int64_t many(int8_t a, int16_t b, int32_t c, int64_t d, uint8_t e, uint16_t f, uint32_t g, uint64_t h, int8_t i, int16_t j, float k, int32_t l, int8_t m, double n) { return a + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8 + i*9 + j*10 + (int64_t)(k*11) + l*12 + m*13 + (int64_t)(n * 14); }
double floats(float a, float b, float c, float d, float e, float f, float g, float h, float i, double j, float k) { return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h + 9*i + 10*j + 11*k; }
void fill(int32_t *p, int n, int32_t v) { for (int i = 0; i < n; i++) p[i] = v + i; }
char *copy(const char *s) { char *r = malloc(strlen(s) + 2); strcpy(r, s); strcat(r, "!"); return r; }
int counter = 5;
int *counterAddress(void) { return &counter; }
''';

const numbersDart = r'''
import 'dart:ffi';
import 'dart:convert';
import 'dart:typed_data';
typedef I = int Function(int);
@Native<Int32 Function(Int32)>() external int abs(int x);
@Native<Double Function(Double)>(symbol: 'cos') external double cosine(double x);
@Native<Pointer<Void> Function(Size)>() external Pointer<Void> malloc(int n);
@Native<Void Function(Pointer<Void>)>() external void free(Pointer<Void> p);
@Native<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, VarArgs<(Int32, Double, Int64)>)>(symbol: 'snprintf') external int snprintf(Pointer<Uint8> to, int n, Pointer<Uint8> f, int a, double b, int c);
@Native<Int32 Function()>() external int noSuchThing();
final class Mem implements Allocator { const Mem(); Pointer<T> allocate<T extends NativeType>(int n, {int? alignment}) => malloc(n).cast(); void free(Pointer p) => freeIt(p); }
void freeIt(Pointer p) => free(p.cast());
const mem = Mem();
String text(Pointer<Uint8> p) { var n = 0; while (p[n] != 0) n++; return utf8.decode(p.asTypedList(n)); }
Pointer<Uint8> native(String s) { final b = utf8.encode(s); final p = mem<Uint8>(b.length + 1); p.asTypedList(b.length + 1)..setAll(0, b)..[b.length] = 0; return p; }
void main() {
  final lib = DynamicLibrary.open('LIBRARY');
  final add = lib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('add'); print(add(2, 3)); print(add(0x7fffffff, 1)); print(add(1 << 40, 3));
  final neg8 = lib.lookup<NativeFunction<Int8 Function(Int8)>>('neg8').asFunction<I>(); for (final n in [1, 127, 128, 200, -128, 300]) print(neg8(n));
  final inc8 = lib.lookupFunction<Uint8 Function(Uint8), I>('inc8'); for (final n in [1, 255, 256, -1]) print(inc8(n));
  print(lib.lookupFunction<Int16 Function(Int16), I>('neg16')(40000)); print(lib.lookupFunction<Uint16 Function(Uint16), I>('inc16')(65535)); print(lib.lookupFunction<Uint32 Function(Uint32), I>('inc32')(0xffffffff)); print(lib.lookupFunction<Uint32 Function(Uint32), I>('inc32')(0x7fffffff));
  print(lib.lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>('add64')(1 << 62, 1 << 61)); final flip = lib.lookupFunction<Bool Function(Bool), bool Function(bool)>('flip'); print(flip(true)); print(flip(false));
  print(lib.lookupFunction<Float Function(Float), double Function(double)>('halff')(0.1)); print(lib.lookupFunction<Double Function(Int8, Float, Double, Int64, Bool, Uint16), double Function(int, double, double, int, bool, int)>('mix')(-3, 1.5, 2.25, 100, true, 70000));
  print(lib.lookupFunction<Int64 Function(Int8, Int16, Int32, Int64, Uint8, Uint16, Uint32, Uint64, Int8, Int16, Float, Int32, Int8, Double), int Function(int, int, int, int, int, int, int, int, int, int, double, int, int, double)>('many')(-1, -2, -3, -4, 5, 6, 7, 8, -9, -10, 11.5, -12, 13, 14.25));
  print(lib.lookupFunction<Double Function(Float, Float, Float, Float, Float, Float, Float, Float, Float, Double, Float), double Function(double, double, double, double, double, double, double, double, double, double, double)>('floats')(1, 2, 3, 4, 5, 6, 7, 8, 9.5, 10.25, 11.5));
  final p = mem<Int32>(10); lib.lookupFunction<Void Function(Pointer<Int32>, Int, Int32), void Function(Pointer<Int32>, int, int)>('fill')(p, 10, 100); print(p.asTypedList(10)); print(p[3]); p[3] = 1 << 33 | 7; print(p[3]); p.value = -1; print(p.cast<Uint8>()[2]); print((p + 4).value); print(p.cast<Uint32>().value); print((p + 3) - 1 == p + 2); print(p.cast<Int8>()[0]); print(p.cast<Uint16>()[1]); p.cast<Float>().value = 0.1; print(p.cast<Float>().value); p.cast<Double>()[1] = 0.1; print(p.cast<Double>()[1]); p.cast<Int64>().value = -5; print(p.cast<Uint64>().value); p.cast<Bool>().value = true; print(p.cast<Bool>().value); print(p.cast<Int16>()[1]);
  final s = native('héllo'); final copy = lib.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>), Pointer<Uint8> Function(Pointer<Uint8>)>('copy'); final c = copy(s); print(text(c)); print(c.runtimeType); mem.free(c); mem.free(s);
  print(abs(-7)); print(cosine(0)); final buf = mem<Uint8>(64), f = native('%d %.2f %lld'); print(snprintf(buf, 64, f, -5, 1.005, 1 << 40)); print(text(buf)); final l = p.asTypedList(4); l[1] = 77; print(p[1]); print(Int32List.sublistView(l, 1, 3)); print(l.buffer.asUint8List(4, 4)); print(l.runtimeType); print(sizeOf<Int32>() + sizeOf<Pointer>() + sizeOf<Long>() + sizeOf<Size>() + sizeOf<WChar>() + sizeOf<Char>());
  final ci = lib.lookup<Int>('counter'); print(ci.value); ci.value = 9; print(lib.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>('counterAddress')()[0]); print(nullptr.address); print(nullptr == Pointer<Int8>.fromAddress(0)); print(Pointer<Int8>.fromAddress(16)); print(Pointer<Int8>.fromAddress(16).hashCode); final pp = mem<Pointer<Int32>>(2); pp[1] = p; pp.value = nullptr; print(pp[1] == p); print(pp.value); print(lib.providesSymbol('add')); print(lib.providesSymbol('nope'));
  final addr = Native.addressOf<NativeFunction<Int32 Function(Int32)>>(abs); print(addr.asFunction<I>()(-9)); print(DynamicLibrary.process().lookupFunction<Int32 Function(Int32), I>('abs')(-11)); print(Abi.current());
  try { lib.lookup<Void>('nope'); } catch (e) { print('$e'.substring(0, 52)); } try { DynamicLibrary.open('/nope.dylib'); } catch (e) { print('$e'.split(':').take(2).join(':')); } try { noSuchThing(); } catch (e) { print('$e'.split("'")[1]); } try { p.asTypedList(-1); } catch (e) { print(e); } Function af = add; print(Function.apply(af, [4, 5])); dynamic d = add; try { d('x', 1); } catch (e) { print(e); } print(add.runtimeType); print(add is int Function(int, int)); print(lib == lib); print(lib.handle.address != 0); lib.close(); try { lib.lookup<Void>('add'); } catch (e) { print(e); }
}
''';

const structsC = r'''
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
typedef struct { int32_t x, y; } Point;
typedef struct { float a, b, c; } Vec3;
typedef struct { double d[4]; } Quad;
typedef struct { int8_t a; int64_t b; int16_t c; } Mixed;
typedef struct { uint8_t bytes[3]; } Small;
typedef struct { Point from, to; char name[8]; } Line;
typedef union { int32_t i; float f; uint8_t b[4]; } Any;
typedef struct __attribute__((packed)) { uint8_t a; uint32_t b; double c; } Pack;
typedef struct { int64_t a, b, c; } Big;
typedef struct { double x; int32_t n; } DI;
typedef struct Node { int32_t v; struct Node *next; } Node;
typedef struct { uint8_t grid[2][3]; Point pts[2]; bool flag; } Grid;
typedef union { double d; float f; } FU;
Point swap(Point p) { Point r = { p.y, p.x }; return r; }
Vec3 scale(Vec3 v, float k) { v.a *= k; v.b *= k; v.c *= k; return v; }
Quad twice(Quad q) { for (int i = 0; i < 4; i++) q.d[i] *= 2; return q; }
Mixed mix(Mixed m) { m.a++; m.b *= 2; m.c--; return m; }
Small small(Small s) { uint8_t t = s.bytes[0]; s.bytes[0] = s.bytes[2]; s.bytes[2] = t; return s; }
Line line(Line l) { Point t = l.from; l.from = l.to; l.to = t; l.name[0] = 'Z'; return l; }
Any any(Any a) { a.i += 1; return a; }
Pack pack(Pack p) { p.a++; p.b++; p.c++; return p; }
Big big(Big b, Big c) { b.a += c.a; b.b += c.b; b.c += c.c; return b; }
DI di(DI d) { d.x += d.n; d.n = -d.n; return d; }
FU fu(FU u) { u.d += 1; return u; }
int32_t sum(Node *n) { int32_t s = 0; for (; n; n = n->next) s += n->v; return s; }
int64_t lots(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, int64_t g, Point p, Mixed m, Small s, Point q, Vec3 v, Vec3 w, Vec3 x, Quad u, DI y) { return a + b + c + d + e + f + g + p.x * 2 + p.y * 3 + m.a * 4 + m.b * 5 + m.c * 6 + s.bytes[0] * 7 + s.bytes[2] * 8 + q.x * 9 + q.y * 10 + (int64_t)(v.a * 11 + w.b * 12 + x.c * 13 + x.a * 14 + u.d[1] * 15 + u.d[3] * 16 + y.x * 17) + y.n * 18; }
int32_t area(Grid *g) { int32_t s = 0; for (int i = 0; i < 2; i++) for (int j = 0; j < 3; j++) s += g->grid[i][j] * (i * 3 + j); return s + g->pts[1].x * 100 + g->pts[0].y * 1000 + g->flag; }
Grid grid(Grid g) { g.grid[1][2]++; g.pts[1].y--; g.flag = !g.flag; return g; }
''';

const structsDart = r'''
import 'dart:ffi';
import 'dart:typed_data';
final class Point extends Struct { @Int32() external int x; @Int32() external int y; String show() => '($x, $y)'; }
final class Vec3 extends Struct { @Float() external double a, b; @Float() external double c; }
final class Quad extends Struct { @Array(4) external Array<Double> d; }
final class Mixed extends Struct { @Int8() external int a; @Int64() external int b; @Int16() external int c; }
final class Small extends Struct { @Array(3) external Array<Uint8> bytes; }
final class Line extends Struct { external Point from, to; @Array(8) external Array<Int8> name; }
final class AnyU extends Union { @Int32() external int i; @Float() external double f; @Array(4) external Array<Uint8> b; }
@Packed(1) final class Pack extends Struct { @Uint8() external int a; @Uint32() external int b; @Double() external double c; }
final class Big extends Struct { @Int64() external int a, b, c; }
final class DI extends Struct { @Double() external double x; @Int32() external int n; }
final class Node extends Struct { @Int32() external int v; external Pointer<Node> next; }
final class Grid extends Struct { @Array(2, 3) external Array<Array<Uint8>> grid; @Array(2) external Array<Point> pts; @Bool() external bool flag; }
final class FU extends Union { @Double() external double d; @Float() external double f; }
final class Ints extends Struct { @Int() external int a; @Long() external int b; @Size() external int c; @Array(3) external Array<Short> s; external Pointer<Int> p; @Array(2) external Array<Pointer<Int8>> ps; }
final class Op extends Opaque {}
@Native<Pointer<Void> Function(Size)>() external Pointer<Void> malloc(int n);
@Native<Void Function(Pointer<Void>)>() external void free(Pointer<Void> p);
final class Mem implements Allocator { const Mem(); Pointer<T> allocate<T extends NativeType>(int n, {int? alignment}) { final p = malloc(n); for (var i = 0; i < n; i++) p.cast<Uint8>()[i] = 0; return p.cast(); } void free(Pointer p) {} }
const mem = Mem();
void main() {
  final lib = DynamicLibrary.open('LIBRARY');
  print([sizeOf<Point>(), sizeOf<Vec3>(), sizeOf<Quad>(), sizeOf<Mixed>(), sizeOf<Small>(), sizeOf<Line>(), sizeOf<AnyU>(), sizeOf<Pack>(), sizeOf<Big>(), sizeOf<Node>(), sizeOf<Grid>(), sizeOf<Ints>()]);
  final p = mem<Point>(3); p.ref.x = 3; p.ref.y = 1 << 33 | 4; p[1].x = 7; (p + 2).ref..x = 8..y = 9; print(p.ref.show()); print(p[1].show()); print((p + 2).ref.y); p[1] = p.ref; print(p[1].show());
  final swap = lib.lookupFunction<Point Function(Point), Point Function(Point)>('swap'); final r = swap(p.ref); print(r.show()); r.x = 100; print(r.show()); print(p.ref.show());
  final v = Struct.create<Vec3>()..a = 1.5..b = 2.5..c = -1; final sc = lib.lookupFunction<Vec3 Function(Vec3, Float), Vec3 Function(Vec3, double)>('scale')(v, 2); print([sc.a, sc.b, sc.c, v.a]);
  final q = Struct.create<Quad>(); for (var i = 0; i < 4; i++) q.d[i] = i + 0.5; final q2 = lib.lookupFunction<Quad Function(Quad), Quad Function(Quad)>('twice')(q); print([for (var i = 0; i < 4; i++) q2.d[i]]); print(q.d.elements);
  final m = Struct.create<Mixed>()..a = 127..b = 1 << 40..c = -32768; final m2 = lib.lookupFunction<Mixed Function(Mixed), Mixed Function(Mixed)>('mix')(m); print([m2.a, m2.b, m2.c]);
  final s = Struct.create<Small>(); s.bytes[0] = 1; s.bytes[1] = 2; s.bytes[2] = 300; final s2 = lib.lookupFunction<Small Function(Small), Small Function(Small)>('small')(s); print([s2.bytes[0], s2.bytes[1], s2.bytes[2]]); try { s.bytes[3]; } catch (e) { print(e); } try { s.bytes[-1] = 1; } catch (e) { print(e); }
  final l = mem<Line>(); l.ref.from = p.ref; l.ref.to.x = 11; l.ref.to.y = 12; l.ref.name[0] = 65; l.ref.name[7] = -1; final l2 = lib.lookupFunction<Line Function(Line), Line Function(Line)>('line')(l.ref); print([l2.from.show(), l2.to.show(), l2.name[0], l2.name[7], l.ref.from.show()]);
  final a = Union.create<AnyU>()..f = 1.0; print(a.i); a.b[0] = 255; final a2 = lib.lookupFunction<AnyU Function(AnyU), AnyU Function(AnyU)>('any')(a); print([a2.i, a2.b[0], a2.f]);
  final k = Struct.create<Pack>()..a = 255..b = 0xffffffff..c = 0.5; final k2 = lib.lookupFunction<Pack Function(Pack), Pack Function(Pack)>('pack')(k); print([k2.a, k2.b, k2.c]);
  final b = Struct.create<Big>()..a = 1..b = 2..c = 3, b2 = Struct.create<Big>()..a = 10..b = 20..c = 30; final b3 = lib.lookupFunction<Big Function(Big, Big), Big Function(Big, Big)>('big')(b, b2); print([b3.a, b3.b, b3.c, b.a]);
  final d = Struct.create<DI>()..x = 1.5..n = 4; final d2 = lib.lookupFunction<DI Function(DI), DI Function(DI)>('di')(d); print([d2.x, d2.n]); final u = Union.create<FU>()..d = 2.5; print(lib.lookupFunction<FU Function(FU), FU Function(FU)>('fu')(u).d);
  Pointer<Node> list = nullptr; for (var i = 0; i < 5; i++) { final n = mem<Node>(); n.ref..v = i..next = list; list = n; } print(lib.lookupFunction<Int32 Function(Pointer<Node>), int Function(Pointer<Node>)>('sum')(list)); print(list.ref.next.ref.v); print(list.ref.next.ref.next.ref.next.ref.next.ref.next == nullptr);
  print(lib.lookupFunction<Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64, Int64, Point, Mixed, Small, Point, Vec3, Vec3, Vec3, Quad, DI), int Function(int, int, int, int, int, int, int, Point, Mixed, Small, Point, Vec3, Vec3, Vec3, Quad, DI)>('lots')(1, 2, 3, 4, 5, 6, 7, p.ref, m, s, r, v, sc, v, q, d));
  final g = mem<Grid>(); for (var i = 0; i < 2; i++) for (var j = 0; j < 3; j++) g.ref.grid[i][j] = i * 10 + j; g.ref.pts[1].x = 5; g.ref.pts[0].y = 6; g.ref.flag = true; print(lib.lookupFunction<Int32 Function(Pointer<Grid>), int Function(Pointer<Grid>)>('area')(g)); final g2 = lib.lookupFunction<Grid Function(Grid), Grid Function(Grid)>('grid')(g.ref); print([g2.grid[1][2], g2.pts[1].y, g2.flag, g.ref.flag]); g.ref.grid[0] = g2.grid[1]; print([for (final row in g.ref.grid.elements) [for (var j = 0; j < 3; j++) row[j]]]); print(g.ref.pts.elements.map((e) => e.show()).toList()); try { g.ref.grid[2]; } catch (e) { print(e); }
  final i = Struct.create<Ints>()..a = 1 << 31..b = 1 << 40..c = -1; i.s[2] = 40000; i.p = Pointer.fromAddress(64); i.ps[1] = Pointer.fromAddress(128); print([i.a, i.b, i.c, i.s[2], i.p.address, i.ps[1].address, i.ps[0].address]); print(i.s.elements); i.s.elements[0] = 9; print(i.s[0]); print(i.ps.elements.length);
  final data = Uint8List(40); final pt = Struct.create<Point>(data, 8); pt.x = 258; print(data.sublist(8, 12)); try { Struct.create<Point>(data, 36); } catch (e) { print(e); } final i32 = Int32List(4); Struct.create<Point>(i32, 1).y = 6; print(i32); print(pt.runtimeType); print(p.ref is Struct); dynamic dp = p.ref; print(dp.x); dp.y = 55; print(p.ref.y); try { dp.x = 'a'; } catch (e) { print(e); } print(p.elementAt(1).ref.show()); Pointer<Int> ip = mem<Int>(3); ip[1] = -7; ip.value = 1 << 32 | 1; print([ip[0], ip[1], (ip + 1).value]); final lp = ip.cast<Long>(); print(lp.value != 0); print(Pointer<Op>.fromAddress(8)); print(l.cast<Point>()[1].show());
}
''';

const namesDart = r'''
import 'dart:ffi';
import 'dart:typed_data';
void main() {
  final lib = DynamicLibrary.process();
  dynamic f = lib.lookupFunction<Int32 Function(Int32 a), int Function(int hello)>('abs');
  try { f('x'); } catch (e) { print(e); }
  try { f(1, 2); } catch (e) { print(e); }
  print(f);
  print(Int32List(2).runtimeType); print(Uint8List(2).runtimeType); print(Int32List.sublistView(Int32List(3), 1).runtimeType); print(ByteData(2).runtimeType); print(Uint8List(1).asUnmodifiableView().runtimeType); print(Float64List(1).runtimeType); print(Uint8List(0).buffer.runtimeType); print(Pointer<Int8>.fromAddress(16).asTypedList(0).runtimeType);
  print(Pointer<Int8>.fromAddress(-16)); print(Pointer<Int8>.fromAddress(255).toString()); print([Pointer<Void>.fromAddress(3)]);print(lib); print('${nullptr.runtimeType}');
  final p = Pointer<Pointer<Int8>>.fromAddress(lib.lookup<Void>('abs').address); print(p.value.runtimeType); print(p.cast<Int8>().runtimeType); print(lib.lookup<Int8>('abs').runtimeType);
}
''';

const callbacksC = r'''
#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
typedef struct { int32_t x, y; } Point;
typedef struct { int64_t a, b, c; } Big;
typedef struct { float a, b, c; } Vec;
int32_t apply(int32_t (*f)(int32_t), int32_t x) { return f(x) + 1; }
double applyD(double (*f)(float, int8_t, double), float a, int8_t b) { return f(a, b, 2.5) * 2; }
void each(void (*f)(int32_t), int n) { for (int i = 0; i < n; i++) f(i); }
Point applyP(Point (*f)(Point, int64_t), Point p) { p.x++; return f(p, 7); }
Big applyB(Big (*f)(Big, Vec, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int8_t, int16_t), Big b) { Vec v = { 1.5f, 2.5f, 3.5f }; return f(b, v, 1, -2, 3, -4, 5, -6, 7, -8, 900); }
int32_t nested(int32_t (*f)(int32_t, void *), int32_t n) { return n <= 0 ? 0 : f(n, f) + 1; }
static void (*stored)(int32_t);
void store(void (*f)(int32_t)) { stored = f; }
void call(int32_t n) { stored(n); }
int compareBytes(const void *a, const void *b);
static void *run(void *f) { for (int i = 0; i < 5; i++) ((void (*)(int32_t, double, Point))f)(i, i / 2.0, (Point){i, -i}); return NULL; }
void inThread(void *f, int wait) { pthread_t t; pthread_create(&t, NULL, run, f); if (wait) pthread_join(t, NULL); }
#include <stdio.h>
void finalize(void *p) { printf("finalize %d\n", *(int32_t *)p); fflush(stdout); }
''';

const throwingDart = r'''
import 'dart:ffi';
import 'dart:async';
final lib = DynamicLibrary.open('LIBRARY');
int dbl(int x) { if (x == 5) throw 'five'; return x * 2; }
void bad(int x) { print(x); if (x == 1) throw StateError('one'); }
void main() {
  runZonedGuarded(() {
  final apply = lib.lookupFunction<Int32 Function(Pointer<NativeFunction<Int32 Function(Int32)>>, Int32), int Function(Pointer<NativeFunction<Int32 Function(Int32)>>, int)>('apply');
  final p = Pointer.fromFunction<Int32 Function(Int32)>(dbl, -100); print(apply(p, 4)); print(apply(p, 5)); print('after');
  final each = lib.lookupFunction<Void Function(Pointer<NativeFunction<Void Function(Int32)>>, Int), void Function(Pointer<NativeFunction<Void Function(Int32)>>, int)>('each');
  each(Pointer.fromFunction(bad), 3); print('done');
  final c = NativeCallable<Int32 Function(Int32)>.isolateLocal((int x) { if (x > 0) throw 'closure'; return 1; }, exceptionalReturn: 3); print(apply(c.nativeFunction, 1)); c.close(); c.close(); try { c.nativeFunction; } catch (e) { print(e); } print(c.keepIsolateAlive);
  }, (e, s) => print('zone $e'));
  print('end');
}
''';

const listeningDart = r'''
import 'dart:ffi';
import 'dart:async';
final lib = DynamicLibrary.open('LIBRARY');
final class Point extends Struct { @Int32() external int x; @Int32() external int y; }
void main() async {
  final run = lib.lookupFunction<Void Function(Pointer<NativeFunction<Void Function(Int32, Double, Point)>>, Int), void Function(Pointer<NativeFunction<Void Function(Int32, Double, Point)>>, int)>('inThread');
  late NativeCallable<Void Function(Int32, Double, Point)> l; var n = 0; final done = Completer();
  l = NativeCallable<Void Function(Int32, Double, Point)>.listener((int a, double b, Point p) { print('$a $b ${p.x} ${p.y}'); if (a == 3) scheduleMicrotask(() => print('micro')); if (++n == 5) { l.close(); done.complete(); } });
  print(l.keepIsolateAlive); run(l.nativeFunction, 1); print('started'); await done.future; print('done');
  final m = NativeCallable<Void Function(Int32, Double, Point)>.listener((int a, double b, Point p) { print('m $a'); if (a == 4) throw 'err'; }); m.keepIsolateAlive = false; run(m.nativeFunction, 1); await Future.delayed(Duration(milliseconds: 20)); print('not reached');
}
''';

const callbacksDart = r'''
import 'dart:ffi';
import 'dart:typed_data';
final lib = DynamicLibrary.open('LIBRARY');
final class Point extends Struct { @Int32() external int x; @Int32() external int y; }
final class Big extends Struct { @Int64() external int a, b, c; }
final class Vec extends Struct { @Float() external double a, b, c; }
int dbl(int x) => x * 2;
double mul(double a, int b, double c) { print('$a $b $c'); return a * b + c; }
Point moved(Point p, int n) { final garbage = [for (var i = 0; i < 100; i++) Uint8List(1000)]; print('${p.x} ${p.y} $n ${garbage.length}'); return Struct.create<Point>()..x = p.y..y = p.x + n; }
Big bigger(Big b, Vec v, int c, int d, int e, int f, int g, int h, int i, int j, int k) { print('${b.a} ${b.b} ${b.c} ${v.a} ${v.b} ${v.c} $c $d $e $f $g $h $i $j $k'); return Struct.create<Big>()..a = b.c..b = b.a + c..c = k; }
typedef NestedC = Int32 Function(Int32, Pointer<Void>);
final nested = lib.lookupFunction<Int32 Function(Pointer<NativeFunction<NestedC>>, Int32), int Function(Pointer<NativeFunction<NestedC>>, int)>('nested');
int back(int n, Pointer<Void> self) { final l = List.generate(50, (i) => 'x$i'); if (n == 3) { try { throw l.last; } catch (e) { print('caught $e'); } } final r = nested(self.cast(), n - 1); return r + l.length; }
int cmp(Pointer<Void> a, Pointer<Void> b) => a.cast<Int32>().value - b.cast<Int32>().value;
@Native<Void Function(Pointer<Void>, Size, Size, Pointer<NativeFunction<Int Function(Pointer<Void>, Pointer<Void>)>>)>() external void qsort(Pointer<Void> p, int n, int s, Pointer<NativeFunction<Int Function(Pointer<Void>, Pointer<Void>)>> f);
@Native<Pointer<Void> Function(Size)>() external Pointer<Void> malloc(int n);
void main() {
  final apply = lib.lookupFunction<Int32 Function(Pointer<NativeFunction<Int32 Function(Int32)>>, Int32), int Function(Pointer<NativeFunction<Int32 Function(Int32)>>, int)>('apply');
  print(apply(Pointer.fromFunction(dbl, 0), 21)); var base = 100; final c = NativeCallable<Int32 Function(Int32)>.isolateLocal((int x) => base += x, exceptionalReturn: -1); print(apply(c.nativeFunction, 5)); print(apply(c.nativeFunction, 6)); print(base); c.close();
  print(lib.lookupFunction<Double Function(Pointer<NativeFunction<Double Function(Float, Int8, Double)>>, Float, Int8), double Function(Pointer<NativeFunction<Double Function(Float, Int8, Double)>>, double, int)>('applyD')(Pointer.fromFunction(mul, 0.0), 1.5, -7));
  final p = Struct.create<Point>()..x = 3..y = 4; final q = lib.lookupFunction<Point Function(Pointer<NativeFunction<Point Function(Point, Int64)>>, Point), Point Function(Pointer<NativeFunction<Point Function(Point, Int64)>>, Point)>('applyP')(Pointer.fromFunction(moved), p); print('${q.x} ${q.y} ${p.x}');
  final b = Struct.create<Big>()..a = 1..b = 2..c = 3; final b2 = lib.lookupFunction<Big Function(Pointer<NativeFunction<Big Function(Big, Vec, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int16)>>, Big), Big Function(Pointer<NativeFunction<Big Function(Big, Vec, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int16)>>, Big)>('applyB')(Pointer.fromFunction(bigger), b); print('${b2.a} ${b2.b} ${b2.c}');
  print(nested(Pointer.fromFunction(back, -1), 6)); final arr = malloc(40).cast<Int32>(); arr.asTypedList(10).setAll(0, [5, 3, 9, 1, 7, 2, 8, 0, 6, 4]); qsort(arr.cast(), 10, 4, Pointer.fromFunction(cmp, 0)); print(arr.asTypedList(10)); print(Pointer.fromFunction<Int32 Function(Int32)>(dbl, 0).asFunction<int Function(int)>()(8));
  lib.lookupFunction<Void Function(Pointer<NativeFunction<Void Function(Int32)>>), void Function(Pointer<NativeFunction<Void Function(Int32)>>)>('store')(NativeCallable<Void Function(Int32)>.isolateLocal((int n) => print('stored $n')).let((c) { c.keepIsolateAlive = false; return c.nativeFunction; })); lib.lookupFunction<Void Function(Int32), void Function(int)>('call')(77);
  for (var i = 0; i < 3000; i++) { final k = NativeCallable<Int32 Function(Int32)>.isolateLocal((int x) => x + i, exceptionalReturn: 0); if (apply(k.nativeFunction, 1) != i + 2) print('wrong $i'); k.close(); }
  final fin = NativeFinalizer(lib.lookup('finalize')); final o = Big2(); fin.attach(o, malloc(4).cast<Int32>().let((m) { m.value = 5; return m.cast(); })); fin.attach(o, nullptr, detach: o); fin.detach(o);
}
class Big2 implements Finalizable {}
extension<T> on T { R let<R>(R Function(T) f) => f(this); }
''';
