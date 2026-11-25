class A {}

class B<T> {
  Type get t => T;
  Type get b => B<T>;
}

Type id<T>() => T;
void main() {
  print(int); // expect: int
  print(A); // expect: A
  print(B<int>().t); // expect: int
  print(B<List<int>>().b); // expect: B<List<int>>
  print(id<String?>()); // expect: String?
  print(A().runtimeType); // expect: A
  print(B<int>().runtimeType == B<int>); // expect: true
  print(1.runtimeType); // expect: int
  print('x'.runtimeType); // expect: String
  print([1].runtimeType); // expect: List<int>
  print([1].runtimeType == List<int>); // expect: true
  print(const [1].runtimeType); // expect: List<int>
  print({}.runtimeType); // expect: _Map<dynamic, dynamic>
  print(<int>{}.runtimeType); // expect: _Set<int>
  print(null.runtimeType); // expect: Null
  print(1.5.runtimeType); // expect: double
  print(true.runtimeType); // expect: bool
  print((() => 1).runtimeType); // expect: () => int
  print(identical(int, int)); // expect: true
  print(int == int); // expect: true
  print({int: 1}[int]); // expect: 1
  switch (A) {
    case A:
      print('a');
  }
  // expect: a
  print(List); // expect: List<dynamic>
  print(Map<String, int>); // expect: Map<String, int>
  dynamic d = 5;
  print(d.runtimeType); // expect: int
  print(main.runtimeType); // expect: () => void
  print(const [int, String]); // expect: [int, String]
  print(
    id<void Function(int, {String? a})>(),
  ); // expect: (int, {String? a}) => void
  Type t = num;
  print(t); // expect: num
  print(id<dynamic>() == id<Object?>()); // expect: false
}
