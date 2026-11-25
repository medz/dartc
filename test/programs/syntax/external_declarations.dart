external int f();
external int g<T>(T a, {int? b});
external int get h;
external set h(int v);

class A {
  A.named();
  external A();
  external factory A.other();
  external int get x;
  external set x(int v);
  external int m(int a, [int? b]);
  external static int s();
  external int operator +(int a);
}

class B extends A {
  B() : super();
}

class C extends A {
  C() : super.named();
  int m(int a, [int? b]) => a;
  int get x => super.x;
}

extension type E(int i) {
  external int z();
}

enum N {
  a;

  external int n();
}

mixin M {
  external int k();
}

class D with M {}

void main() {
  for (final use in <Object? Function()>[
    () => f(),
    () => g<int>(1, b: 2),
    () => h,
    () => h = 2,
    () => A(),
    () => A.other(),
    () => A.named().x,
    () => A.named().x = 1,
    () => A.named().m(1, 2),
    () => A.s(),
    () => A.named() + 1,
    () => B(),
    () => C().m(1),
    () => C().x,
    () => (C() as dynamic).x,
    () => (A.named() as dynamic).m(1),
    () => f,
    () => (f as dynamic)(),
    () => A.s,
    () => A.named().m,
    () => A.named().m(3),
    () => E(1).z(),
    () => N.a.n(),
    () => D().k(),
  ]) {
    try {
      print(use() is Function ? 'function' : use());
    } catch (e) {
      print(e.runtimeType);
    }
  }
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: 1
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: function
  // expect: NoSuchMethodError
  // expect: function
  // expect: function
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  // expect: NoSuchMethodError
  print('end'); // expect: end
}
