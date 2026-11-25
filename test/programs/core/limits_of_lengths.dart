import 'dart:typed_data';

void t(void Function() f) {
  try {
    f();
    print('ok');
  } on OutOfMemoryError catch (e) {
    print(e);
  } catch (e) {
    print('${e.runtimeType} $e');
  }
}

void main() {
  for (final n in [0x4000000000000000, -1]) {
    t(() => List<int>.filled(n, 1));
    t(() => List<int>.generate(n, (i) => i));
    t(() => List<int?>.filled(n, null, growable: true));
    t(() => Uint8List(n));
    t(() => Float64List(n));
    t(() => List.filled(n, 0).length);
  }
  // expect: Out of Memory
  // expect: Out of Memory
  // expect: Out of Memory
  // expect: Out of Memory
  // expect: Out of Memory
  // expect: Out of Memory
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..4611686018427387903: -1
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
  // expect: RangeError RangeError (length): Invalid value: Not in inclusive range 0..576460752303423487: -1
}
