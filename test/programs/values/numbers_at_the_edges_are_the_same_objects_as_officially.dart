import 'dart:typed_data';

double fromBits(int bits) => (ByteData(8)..setUint64(0, bits)).getFloat64(0);
int toBits(double value) => (ByteData(8)..setFloat64(0, value)).getUint64(0);

void main() {
  final exact = int.parse('9007199254740992');
  final rounded = exact.toDouble();
  final next = exact + 1;
  print('${exact == rounded}|${rounded == next}|${exact == next}'); // expect: true|true|false
  print(rounded.hashCode == next.hashCode); // expect: false
  print(<num>{rounded}.contains(next)); // expect: false
  print('${rounded < next}|${rounded.compareTo(next)}'); // expect: false|-1
  final a = int.parse('9223372036854775807');
  final b = double.parse('9223372036854775808.0');
  print('${a == b}|${b == a}|${a < b}|${b > a}'); // expect: true|true|false|false
  print(a.hashCode == b.hashCode); // expect: true
  print('${{a}.contains(b)}|${{b}.contains(a)}'); // expect: true|true
  for (final d in [
    0.0,
    -0.0,
    1.0,
    1e18,
    9.2e18,
    -9.2e18,
    9223372036854775807.0,
    -9223372036854775808.0,
    1.5,
    double.nan,
    double.infinity,
  ]) {
    print('$d ${d.hashCode}');
  }
  // expect: 0.0 0
  // expect: -0.0 0
  // expect: 1.0 11601
  // expect: 1000000000000000000.0 781410608
  // expect: 9200000000000000000.0 405328623
  // expect: -9200000000000000000.0 405220670
  // expect: 9223372036854776000.0 15352
  // expect: -9223372036854776000.0 5800
  // expect: 1.5 4609434219686920192
  // expect: NaN 4609434220760662016
  // expect: Infinity 4607182420946452480
  for (final i in [0, 1, -1, 1 << 62, -(1 << 63), 9223372036854775807]) {
    print('$i ${i.hashCode}');
  }
  // expect: 0 0
  // expect: 1 11601
  // expect: -1 0
  // expect: 4611686018427387904 2900
  // expect: -9223372036854775808 5800
  // expect: 9223372036854775807 15352
  final x = fromBits(0x7ff8000000000001),
      y = fromBits(0x7ff8000000000002),
      z = fromBits(0x7ff8000000000001);
  print('${toBits(x).toRadixString(16)} ${toBits(y).toRadixString(16)}'); // expect: 7ff8000000000001 7ff8000000000002
  print('${identical(x, y)} ${identical(x, z)} ${identical(x, x)}'); // expect: false true true
  print('${identical(0.0, -0.0)} ${identical(double.nan, double.nan)}'); // expect: false true
  Object o1 = x, o2 = y;
  print(identical(o1, o2)); // expect: false
}
