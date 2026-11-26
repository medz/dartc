import 'dart:typed_data';

void main() {
  print((Float32x4(1, 2, 3, 4) * Float32x4.splat(2)).y); // expect: 4.0
  final list = Float64x2List(2);
  list[0] = Float64x2(1, 2);
  print(list[0].y); // expect: 2.0
  print(Int32x4(1, 2, 3, 4).x); // expect: 1
  final a = Float32x4(1.1, -2, 3.5, -0.0);
  print([a.x, a.y, a.z, a.w]); // expect: [1.100000023841858, -2.0, 3.5, -0.0]
  print(a.signMask); // expect: 10
  print(a.abs().x); // expect: 1.100000023841858
  print(a.shuffle(Float32x4.wzyx).x); // expect: -0.0
  print(a.lessThan(Float32x4.zero()).signMask); // expect: 2
  final i = Int32x4(-1, 0x7fffffff, 0x80000000, 5);
  print([i.x, i.y, i.z, i.w, i.signMask]); // expect: [-1, 2147483647, -2147483648, 5, 5]
  print((i + Int32x4(1, 1, 1, 1)).y); // expect: -2147483648
  print(Int32x4.fromFloat32x4Bits(Float32x4(1, 0, -1, 2)).x); // expect: 1065353216
  print(Float32x4.fromInt32x4Bits(Int32x4(0x3f800000, 0, 0, 0)).x); // expect: 1.0
  print(i.select(Float32x4(1, 2, 3, 4), Float32x4(5, 6, 7, 8)).y); // expect: 2.0
  final f = Float32x4List(3);
  f[1] = a;
  print(f[1].x); // expect: 1.100000023841858
  print(f.buffer.asFloat32List()[4]); // expect: 1.100000023841858
  final view = Float32List(8).buffer.asFloat32x4List();
  view[1] = Float32x4.splat(9);
  print(view[1].w); // expect: 9.0
  print(Float64x2(1.5, -2).sqrt().x); // expect: 1.224744871391589
  print((Float32x4(1, 4, 9, 16).sqrt()).w); // expect: 4.0
  print(a); // expect: V128
  try {
    a.shuffle(300);
  } catch (e) {
    print(e);
  }
  // expect: RangeError (mask): Invalid value: Not in inclusive range 0..255: 300
  print(Float32x4(1, 2, 3, 4).clamp(Float32x4.splat(2), Float32x4.splat(3)).w);
  // expect: 3.0
  print(Float64x2(3, 4).scale(0.5).y); // expect: 2.0
  print(Int32x4.bool(true, false, true, false).flagZ); // expect: true
  print(Float32x4List(2).length); // expect: 2
}
