// A program that passes the addresses of parts of objects to C.

const addressesDart = r'''
import 'dart:ffi';
import 'dart:typed_data';

final class Inner extends Struct {
  @Int16()
  external int a;
  @Float()
  external double b;
}

final class S extends Struct {
  @Int32()
  external int v;
  @Bool()
  external bool flag;
  external Inner inner;
  @Array(4)
  external Array<Uint8> bytes;
  @Array(2, 3)
  external Array<Array<Int16>> grid;
  @Array(2)
  external Array<Inner> inners;
  @Array(2)
  external Array<Double> doubles;
  @Array(3)
  external Array<Bool> flags;

  void setOwn() {
    fill(v.address, 2, 4);
    fill(this.bytes[1].address, 3, 2);
  }
}

final class U extends Union {
  @Int32()
  external int i;
  @Double()
  external double d;
}

@Native<Pointer<Void> Function(Pointer<Void>, Int32, Size)>(symbol: 'memset', isLeaf: true)
external Pointer<Void> fill(Pointer<Void> to, int value, int count);

@Native<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Size)>(symbol: 'memcpy', isLeaf: true)
external Pointer<Void> copy(Pointer<Void> to, Pointer<Void> from, int count);

@Native<Size Function(Pointer<Uint8>)>(isLeaf: true)
external int strlen(Pointer<Uint8> s);

@Native<Pointer<Void> Function(Size)>()
external Pointer<Void> malloc(int n);

int count = 0;
Uint8List next(Uint8List l) {
  count++;
  return l;
}

int index(int i) {
  count += 10;
  return i;
}

void main() {
  final bytes = Uint8List.fromList([65, 66, 67, 0, 68, 0]);
  for (var i = 0; i < 5; i++) {
    print(strlen(bytes[i].address));
  }
  print(strlen(Uint8List.sublistView(bytes, 1)[1].address));
  print(strlen(next(bytes)[index(4)].address));
  print(count);
  final shorts = Int16List(4);
  fill(shorts[1].address.cast(), 1, 2);
  print(shorts);
  final longs = Int64List(3), doubles = Float64List(3), floats = Float32List(3);
  fill(longs[2].address, 255, 8);
  print(longs);
  doubles[0] = 2.5;
  copy(doubles[2].address, doubles[0].address, 8);
  print(doubles);
  floats[1] = 0.5;
  copy(floats[0].address, floats[1].address, 4);
  print(floats);
  final words = Uint32List(2), halves = Uint16List(2), signed = Int8List(2);
  fill(words[1].address, 1, 4);
  fill(halves[1].address, 1, 2);
  fill(signed[1].address, 200, 1);
  print((words, halves, signed));
  final s = Struct.create<S>();
  fill(s.v.address, 1, 4);
  print(s.v);
  fill(s.flag.address, 1, 1);
  print(s.flag);
  fill(s.inner.a.address, 1, 2);
  s.inner.b = 1.5;
  copy(s.inners[1].b.address, s.inner.b.address, 4);
  print((s.inner.a, s.inners[1].b));
  fill(s.bytes[2].address, 7, 2);
  print([for (var i = 0; i < 4; i++) s.bytes[i]]);
  fill(s.grid[1][1].address, 1, 2);
  print(s.grid[1][1]);
  fill(s.flags[1].address, 1, 1);
  print((s.flags[0], s.flags[1]));
  s.doubles[0] = 0.25;
  copy(s.doubles[1].address, s.doubles[0].address, 8);
  print(s.doubles[1]);
  s.setOwn();
  print((s.v, s.bytes[1], s.bytes[2]));
  for (final i in [4, -1]) {
    try {
      fill(s.bytes[index(i)].address, 7, 1);
    } catch (e) {
      print(e.runtimeType);
    }
  }
  final u = Union.create<U>();
  u.d = 1;
  fill(u.i.address, 0, 4);
  print(u.d);
  final p = malloc(sizeOf<S>()).cast<S>();
  fill(p.ref.inner.a.address, 3, 2);
  print(p.ref.inner.a);
  fill(p.ref.bytes[3].address, 9, 1);
  print((p + 0).ref.bytes[3]);
  fill((s.v).address, 5, 1);
  print(s.v);
  fill(s.inner.address.cast(), 0, 2);
  fill(s.bytes.address.cast(), 0, 4);
  print((s.inner.a, s.bytes[2]));
}
''';
