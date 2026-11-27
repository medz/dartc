// What members of `this` give needs no check in classes and mixins, but does
// in extensions, where `this` may be of a subtype.
class F<T> {
  final void Function(T) f;
  F(this.f);
  void Function(T) get g => f;
  void Function(T) m() => f;

  void run(T value) {
    f(value);
    this.f(value);
    g(value);
    m()(value);
    [value].forEach((value) => f(value));
  }

  void Function(T) read() => this.g;
}

enum E<T> {
  one<int>();

  void Function(T) get g =>
      (T value) => print('E $value');
  void run(T value) => g(value);
}

class C<T> {
  void Function(T) get g =>
      (T value) => print('C $value');
}

mixin M<T> on C<T> {
  void run(T value) => g(value);
  void Function(T) read() => g;
}

class D<T> extends C<T> with M<T> {}

extension Reads<T> on F<T> {
  void Function(T) read2() => f;
}

void go(void Function() f) {
  try {
    f();
    print('ok');
  } on TypeError {
    print('T');
  }
}

void main() {
  F<num> f = F<int>((n) => print('f $n'));
  go(() => f.run(1));
  // expect: f 1
  // expect: f 1
  // expect: f 1
  // expect: f 1
  // expect: f 1
  // expect: ok
  go(() => f.read()); // expect: T
  go(() => f.g); // expect: T
  go(() => f.read2()); // expect: T
  go(() => E.one.run(2));
  // expect: E 2
  // expect: ok
  M<num> d = D<int>();
  go(() => d.run(3));
  // expect: C 3
  // expect: ok
  go(() => d.read()); // expect: T
  F<int> k = F<int>((n) => print('k $n'));
  go(() => k.read2()(4));
  // expect: k 4
  // expect: ok
}
