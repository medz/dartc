// official: Dart 3.14.0 tells function types apart by the order of named parameters (#60).
typedef AB = void Function({int? a, int? b});
typedef BA = void Function({int? b, int? a});
void ba({int? b, int? a}) {}
void ab({int? a, int? b}) {}
void requiredB({required int b, String? a}) {}
void mixed(num value, {required String z, bool? a}) {}

class C {
  void ba({int? b, int? a}) {}
}

void main() {
  final first = ba.runtimeType, second = ab.runtimeType;
  print(first); // expect: ({int? b, int? a}) => void
  print(second); // expect: ({int? a, int? b}) => void
  print(first == second); // expect: true
  print(C().ba.runtimeType == first); // expect: true
  print({first: 1, second: 2}[C().ba.runtimeType]); // expect: 2
  print(BA); // expect: ({int? a, int? b}) => void
  print(AB == BA); // expect: true
  print(first == BA); // expect: true
  print(second == BA); // expect: true
  Object f = ba;
  print(f is AB); // expect: true
  print(f is void Function({int? b})); // expect: true
  print(f is void Function({int? c})); // expect: false
  f = mixed;
  print(f.runtimeType); // expect: (num, {required String z, bool? a}) => void
  print(f is void Function(int, {bool? a, required String z})); // expect: true
  print(f is void Function(int, {bool? a})); // expect: false
  f = requiredB;
  print(f is void Function({String? a, required int b})); // expect: true
  print(f is void Function({String? a, int b})); // expect: false
  print(f is void Function({required num b})); // expect: false
}
