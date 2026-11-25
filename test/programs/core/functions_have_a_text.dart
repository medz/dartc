class A {
  A();
  A.n();
  int m() => 1;
  static int s() => 2;
  int get g => 3;
  int operator +(int o) => 1;
  factory A.f() => A();
}

int top(int x) => x;
T gen<T>(T t) => t;

class G<T> {
  G();
  G.x();
  T? m(T t) => t;
}

void main() {
  int local() => 1;
  print(local); // expect: Closure: () => int
  print(top); // expect: Closure: (int) => int from Function 'top': static.
  print(A.s); // expect: Closure: () => int from Function 's': static.
  print(A().m); // expect: Closure: () => int from Function 'm':.
  print(A.new); // expect: Closure: () => A from Function 'A.': static.
  print(A.n); // expect: Closure: () => A from Function 'A.n': static.
  print(A.f); // expect: Closure: () => A from Function 'A.f': static.
  int Function(int) g = gen;
  print(g); // expect: Closure: (int) => int from Function 'gen': static.
  print(
    G<int>.new,
  ); // expect: Closure: () => G<int> from Function 'G.': static.
  print(G<int>().m); // expect: Closure: (Object?) => int? from Function 'm':.
  print(
    (int x, {required String y}) => x,
  ); // expect: Closure: (int, {required String y}) => int
  print([1].add); // expect: Closure: (Object?) => void from Function 'add':.
  print(
    'a'.substring,
  ); // expect: Closure: (int, [int?]) => String from Function 'substring':.
  print(identical); // expect: Closure: (Object?, Object?) => bool from Function 'identical': static.
  print(
    A().m.toString,
  ); // expect: Closure: () => String from Function 'toString':.
  print((A().m).call); // expect: Closure: () => int from Function 'm':.
  print(
    print,
  ); // expect: Closure: (Object?) => void from Function 'print': static.
}
