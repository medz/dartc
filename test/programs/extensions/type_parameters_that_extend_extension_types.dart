extension type E<T>(T value) {
  T get() => value;
  T get got => value;
  E<T> operator +(int i) => this;
  void set it(T v) => print(v);
  T call(int i) => value;
  T operator [](int i) => value;
}
extension type U(int v) {
  int operator -() => -v;
  int operator ~() => ~v;
  dynamic operator +(int i) => U(v + i);
  dynamic operator -(int i) => U(v - i);
}
extension type N(int? v) {
  int? n() => v;
  static int s = 1;
}
extension type O(int v) implements Object {
  int o() => v;
}
int read<B extends E<int>>(B value) => value.get();
int read2<B extends E<int>>(B value) => value.got;
void read4<B extends E<int>>(B value) { value.it = 3; }
int read5<B extends E<int>>(B value) => value(1);
int read6<B extends E<int>>(B value) => value[1];
Object read7<B extends E<int>>(B value) => value.get;
int negate<B extends U>(B b) => -b;
int flip<B extends U>(B b) => ~b;
void add<B extends U>(B b) { b += 5; print((b as U).v); }
void increment<B extends U>(B b) { b++; ++b; print((b as U).v); }
void decrement<B extends U>(B b) { b--; --b; print((b as U).v); }
int? n<B extends N>(B b) => b.n();
int o<B extends O>(B b) => b.o();
int two<C extends E<int>, B extends C>(B value) => value.get();
String str<B extends E<int>>(B value) => value.toString();
class K<B extends E<int>> {
  final B b;
  K(this.b);
  int m() => b.get();
}
void main() {
  print(read(E(1))); // expect: 1
  print(read2(E(2))); // expect: 2
  read4(E(4)); // expect: 3
  print(read5(E(5))); // expect: 5
  print(read6(E(6))); // expect: 6
  print(read7(E(6)) is Function); // expect: true
  print(negate(U(3))); // expect: -3
  print(flip(U(3))); // expect: -4
  add(U(3)); // expect: 8
  increment(U(3)); // expect: 5
  decrement(U(3)); // expect: 1
  print(n(N(null))); // expect: null
  print(o(O(7))); // expect: 7
  print(two(E(8))); // expect: 8
  print(str(E(8))); // expect: 8
  print(K(E(9)).m()); // expect: 9
}
