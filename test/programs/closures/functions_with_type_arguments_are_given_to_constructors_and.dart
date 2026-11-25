extension type const Box<T>(T value) {
  const Box.two(T a, int b) : value = a;
}

typedef Bounded<T extends num> = Box<T>;
typedef Fixed<T> = Box<int>;

extension type Number._(int value) {
  factory([int value]) = Number.destination;
  factory again([int value]) = Number;
  new destination([int value = 7]) : value = value;
}

extension type P<A, B>((A, B) v) {
  new fields(A a, B b) : v = (a, b);
}

typedef Flip<A, B> = P<B, A>;
void main() {
  const bounded = Bounded.new;
  print(bounded<int>(6).value); // expect: 6
  final b2 = Box.new;
  print(b2<int>(3).value); // expect: 3
  print(b2('a').value); // expect: a
  final make = Number.again;
  print(make().value); // expect: 7
  print(make(2).value); // expect: 2
  final f = Flip.fields;
  print(f<int, String>('x', 3).v); // expect: (x, 3)
  dynamic d = f;
  print(d('x', 4)); // expect: (x, 4)
  try {
    d<int, String>(1, 1);
  } catch (e) {
    print(e);
  }
  // expect: type 'int' is not a subtype of type 'String' of 'a'
  print(Function.apply(b2, [4])); // expect: 4
  Box<int> Function(int) k = Box.new;
  print(k(5)); // expect: 5
  print(Box.two.runtimeType); // expect: <Y0>(Y0, int) => Y0
  more();
  // expect: (7, 3, 2)
  // expect: (8, 3, 2)
  // expect: (8, [3], D<List<dynamic>>)
  // expect: (7, 5)
  // expect: (7, 4, 6)
  // expect: type 'String' is not a subtype of type 'int?' of 'a'
  // expect: 3
  // expect: 3
  // expect: 7
  // expect: (int?, null, 3)
  // expect: (dynamic, 4, 3)
  // expect: (dynamic, 1, 3)
  // expect: (int, 5, 3)
}

class D<T> {
  final T? a;
  final int b;
  D([this.a, this.b = 7]);
  D.n({this.a, this.b = 8});
}

typedef DI<X> = D<List<X>>;
typedef DF<X> = D<int>;
void more() {
  final f = D.new;
  print((f<int>().b, f<int>(3).a, f(1, 2).b));
  final g = D.n;
  print((g<int>().b, g<int>(a: 3).a, g(b: 2).b));
  const h = DI.n;
  print((h<int>().b, h<int>(a: [3]).a, h(b: 2).runtimeType));
  const k = DF.new;
  print((k<String>().b, k<String>(5).a));
  dynamic d = k;
  print((d().b, d(4).a, d<String>(4, 6).b));
  try {
    d('x');
  } catch (e) {
    print(e);
  }
  print(Function.apply(h, [], {#b: 3}).b);
  print(Function.apply(k, [3]).a);
  final D<int> Function([int?]) p = D.new;
  print(p().b);
  T id<T>([T? x, int y = 3]) {
    print((T, x, y));
    return x as T;
  }

  id<int?>();
  dynamic i2 = id;
  i2(4);
  Function.apply(id, [1]);
  final int Function([int?]) q = id;
  q(5);
}
