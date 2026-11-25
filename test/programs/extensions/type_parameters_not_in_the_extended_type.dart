extension D<T> on int {
  Type get type => T;
  set any(T value) => print((T, value));
  List<T> list(T a) => [a];
  Map<T, U> map<U>(T a, U b) => {a: b};
  T operator +(T other) => other;
  T operator [](T at) => at;
}

extension B<T extends num, U extends List<T>> on String {
  (Type, Type) get types => (T, U);
}

extension M<A, B> on List<A> {
  (Type, Type) get types => (A, B);
  B? none() => null;
}

extension<T> on double {
  Type get own => T;
}

class C<T> {
  void m() {
    print(D<T>(1).type);
    print(1.type);
    print(D<List<T>>(1).list([]).runtimeType);
  }
}

void main() {
  print(D<String>(1).type); // expect: String
  print(1.type); // expect: dynamic
  D<String>(1).any = 'a'; // expect: (String, a)
  1.any = 2; // expect: (dynamic, 2)
  print(D<String>(1).list('a').runtimeType); // expect: List<String>
  print(1.list('a').runtimeType); // expect: List<dynamic>
  print(D<String>(1).map<int>('a', 2).runtimeType); // expect: _Map<String, int>
  print(D<String>(1)['c']); // expect: c
  print('a'.types); // expect: (num, List<num>)
  print(B<int, List<int>>('a').types); // expect: (int, List<int>)
  print([1].types); // expect: (int, dynamic)
  print(M<num, String>([1]).types); // expect: (num, String)
  print([1].none()); // expect: null
  print(1.5.own); // expect: dynamic
  final f = D<bool>(1).list;
  print(f(true).runtimeType); // expect: List<bool>
  print(f.runtimeType); // expect: (bool) => List<bool>
  C<int>().m();
  // expect: int
  // expect: dynamic
  // expect: List<List<int>>
}
