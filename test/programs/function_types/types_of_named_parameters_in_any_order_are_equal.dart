// official: Dart 3.14.0 tells these types apart by the order of the names (runtime/vm/object.cc).
typedef F = void Function({int a, int b});
typedef G = void Function({int a, String b});
typedef H = void Function({int a, required int b});

void f({int b = 0, int a = 0}) {}
void g({int a = 0, int b = 0}) {}

void main() {
  print(f.runtimeType == F); // expect: true
  print(g.runtimeType == F); // expect: true
  print(f.runtimeType == g.runtimeType); // expect: true
  print(f.runtimeType.hashCode == (F).hashCode); // expect: true
  print({F: 1}[f.runtimeType]); // expect: 1
  print(f.runtimeType == G); // expect: false
  print(f.runtimeType == H); // expect: false
  print(f is F); // expect: true
  print(f.runtimeType); // expect: ({int b, int a}) => void
  print(F); // expect: ({int a, int b}) => void
}
