external int f();
external int g<T>(T a, {int? b});
external int get h;
external set h(int v);

class A {
  A.named();
  external A(int i);
  external factory A.other(int i);
  external int get x;
  external set x(int v);
  external int m(int a, [int? b]);
  external static int s(int i);
  external int operator +(int a);
  noSuchMethod(i) => 'mine';
}

extension E on int {
  external int z(int a);
  external int get y;
}

extension type T(int i) {
  external int z(int a);
}

void main() {
  for (final use in <Object? Function()>[
    () => f(),
    () => g<int>(1, b: 2),
    () => h,
    () => h = 2,
    () => A(1),
    () => A.other(2),
    () => A.named().x,
    () => A.named().x = 1,
    () => A.named().m(1, 2),
    () => A.s(3),
    () => A.named() + 1,
    () => 1.z(2),
    () => 1.y,
    () => T(1).z(2),
  ]) {
    try {
      print(use());
    } catch (e) {
      print(e);
    }
  }
  // expect: NoSuchMethodError: No top-level method 'f' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: f()
  // expect: NoSuchMethodError: No top-level method 'g' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: g()
  // expect: NoSuchMethodError: No top-level getter 'h' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: h
  // expect: NoSuchMethodError: No top-level setter 'h=' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: h=
  // expect: NoSuchMethodError: No constructor 'A.' with matching arguments declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: new A.()
  // expect: Found: new A.(int) => A
  // expect: NoSuchMethodError: No constructor 'A.other' with matching arguments declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: new A.other()
  // expect: Found: new A.other(int) => A
  // expect: NoSuchMethodError: No static getter 'x' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: x
  // expect: NoSuchMethodError: No static setter 'x=' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: x=
  // expect: NoSuchMethodError: No static method 'm' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: m()
  // expect: NoSuchMethodError: No static method 's' with matching arguments declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: s()
  // expect: Found: s(int) => int
  // expect: NoSuchMethodError: No static method '+' declared in class 'A'.
  // expect: Receiver: A
  // expect: Tried calling: +()
  // expect: NoSuchMethodError: No top-level method 'E|z' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: E|z()
  // expect: NoSuchMethodError: No top-level method 'E|get#y' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: E|get#y()
  // expect: NoSuchMethodError: No top-level method 'T|z' declared.
  // expect: Receiver: top-level
  // expect: Tried calling: T|z()
}
