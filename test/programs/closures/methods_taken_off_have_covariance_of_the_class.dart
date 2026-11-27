class Base {
  void f(num x) => print('f $x');
}

abstract class Narrow extends Base {
  void f(covariant int x);
}

class Child extends Narrow {}

class Other extends Base {
  void f(covariant int x) => print('other $x');
}

class I {
  void f(covariant int x) {}
}

class Mixed extends Base implements I {}

void call(Object f, Object? value) {
  try {
    (f as dynamic)(value);
  } on TypeError {
    print('TypeError');
  }
}

void main() {
  final Object f = Child().f;
  print(f is void Function(Object?)); // expect: true
  print(f.runtimeType); // expect: (Object?) => void
  call(f, 3); // expect: f 3
  call(f, 1.5); // expect: f 1.5
  call(f, 'x'); // expect: TypeError
  print(Other().f.runtimeType); // expect: (Object?) => void
  print(Mixed().f.runtimeType); // expect: (Object?) => void
  print(Base().f.runtimeType); // expect: (num) => void
  print(Base().f is void Function(Object?)); // expect: false
  final Narrow n = Child();
  n.f(2); // expect: f 2
}
