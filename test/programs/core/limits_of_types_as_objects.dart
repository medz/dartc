class P<T> {
  Type get t => T;
  Type get l => List<T>;
}

Type reify<T>() => T;
void main() {
  print(identical(1.runtimeType, 2.runtimeType)); // expect: true
  print(identical(1.runtimeType, int)); // expect: true
  print(identical([1].runtimeType, [2].runtimeType)); // expect: true
  print(identical([1].runtimeType, <int>[2].runtimeType)); // expect: true
  print(identical(P<int>().runtimeType, P<int>().runtimeType)); // expect: true
  print(identical(reify<int>(), int)); // expect: true
  print(identical(reify<List<int>>(), const [List<int>][0])); // expect: true
  print(identical((1, 2).runtimeType, (3, 4).runtimeType)); // expect: true
  print({P<int>().t, int, reify<int>()}.length); // expect: 1
}
