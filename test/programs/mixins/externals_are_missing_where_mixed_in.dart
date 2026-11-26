mixin M {
  external int x;
  external void m();
  external int get g;
}

class C = Object with M;

class D extends Object with M {}

class E with M {}

void t(void Function() f) {
  try {
    f();
  } on NoSuchMethodError catch (error) {
    print(error);
  }
}

void main() {
  t(() => C().x = 1);
  // expect: NoSuchMethodError: No static setter 'x=' declared in class 'C'.
  // expect: Receiver: C
  // expect: Tried calling: x=
  t(() => C().x);
  // expect: NoSuchMethodError: No static getter 'x' declared in class 'C'.
  // expect: Receiver: C
  // expect: Tried calling: x
  t(() => C().m());
  // expect: NoSuchMethodError: No static method 'm' declared in class 'C'.
  // expect: Receiver: C
  // expect: Tried calling: m()
  t(() => C().g);
  // expect: NoSuchMethodError: No static getter 'g' declared in class 'C'.
  // expect: Receiver: C
  // expect: Tried calling: g
  t(() => D().x = 1);
  // expect: NoSuchMethodError: No static setter 'x=' declared in class '_D&Object&M'.
  // expect: Receiver: _D&Object&M
  // expect: Tried calling: x=
  t(() => E().m());
  // expect: NoSuchMethodError: No static method 'm' declared in class '_E&Object&M'.
  // expect: Receiver: _E&Object&M
  // expect: Tried calling: m()
}
