import 'dart:async';

R id<R>(R a) => a;
bool phantom<T>(Object c) => c is T;
class Container<T>(final T value);
typedef PA<A, B> = Container<A>;
const concrete = id<int>;
const gen = id;
const through = gen<int>;
const sel = phantom<int>;
const fb = phantom<String>;
const m1 = PA<int, String>.new;
const raw = PA.new;
const m2 = raw<int, String>;
void main() async {
  print(concrete == through); // expect: true
  print(identical(concrete, through)); // expect: true
  print(sel == (phantom<int>)); // expect: true
  print(sel != (phantom<String>)); // expect: true
  print(fb == (phantom<String>)); // expect: true
  print(sel(1)); // expect: true
  print(fb(1)); // expect: false
  print(fb('a')); // expect: true
  print(m1 == Container<int>.new); // expect: true
  final x = m1(3);
  print(x.runtimeType); // expect: Container<int>
  print(Container<int>.new == Container<int>.new); // expect: true
  print((id<int>) == (id<int>)); // expect: true
  T f<T>() {
    return (id<T>) == (id<T>) ? 1 as T : 2 as T;
  }

  print(f<int>()); // expect: 1
  int Function(int) p = id;
  int Function(int) q = id;
  print(p == q); // expect: true
  T loc<T>(T a) => a;
  final l1 = loc<int>, l2 = loc<int>;
  print((
    l1 == l2,
    l1.hashCode == l2.hashCode,
    identical(l1, l2),
    l1 == (loc<String>),
  )); // expect: (true, true, false, false)
  final o = Q();
  print((
    (o.m<int>) == (o.m<int>),
    (o.m<int>) == (o.m<num>),
    (o.m<int>) == (Q().m<int>),
  )); // expect: (true, false, false)
}

class Q {
  T m<T>(T a) => a;
}
