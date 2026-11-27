import 'dart:typed_data';

import_() => 1;
void main() {
  final b = Uint8List(4);
  b[0] = 300;
  b[1] = -1;
  print(b); // expect: [44, 255, 0, 0]
  final w = b.buffer.asUint16List();
  w[1] = 0xabcd;
  print(b); // expect: [44, 255, 205, 171]
  final d = ByteData(16);
  d.setFloat64(0, 1.5);
  d.setInt32(8, -7, Endian.little);
  print(d.getUint8(0)); // expect: 63
  print(d.getFloat64(0)); // expect: 1.5
  print(d.getInt32(8, Endian.little)); // expect: -7
  print(d.getInt32(8)); // expect: -100663297
  print(Float32List.fromList([0.1])[0]); // expect: 0.10000000149011612
  print(Int8List.fromList([200])); // expect: [-56]
  print(Uint32List(2)..[1] = -1); // expect: [0, 4294967295]
  print(Uint8ClampedList.fromList([300, -5, 7])); // expect: [255, 0, 7]
  print(Uint8List.sublistView(b, 1, 3)); // expect: [255, 205]
  print(b.sublist(2)); // expect: [205, 171]
  b.setRange(1, 4, b);
  print(b); // expect: [44, 44, 255, 205]
  final bytes = Uint8List.fromList([for (var i = 0; i < 16; i++) i]);
  Uint8List.sublistView(
    bytes,
    3,
  ).setRange(0, 10, Uint8List.sublistView(bytes, 1));
  print(bytes); // expect: [0, 1, 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15]
  print(Int64List.fromList([1 << 62, -1])); // expect: [4611686018427387904, -1]
  try {
    b[4];
  } catch (e) {
    print(e);
  }
  // expect: RangeError (length): Invalid value: Not in inclusive range 0..3: 4
  try {
    Uint8List(-1);
  } catch (e) {
    print(e);
  }
  // expect: RangeError (length): Invalid value: Not in inclusive range 0..4611686018427387903: -1
  final v = Uint8List.view(b.buffer, 1, 2);
  v[0] = 77;
  print('$b ${v.length} ${v.offsetInBytes}'); // expect: [44, 77, 255, 205] 2 1
  print(b.map((x) => x + 1).toList()); // expect: [45, 78, 256, 206]
}
