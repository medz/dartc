class A {
  noSuchMethod(Invocation i) {
    print(
      '${i.memberName} ${i.positionalArguments} ${i.namedArguments} ${i.isMethod} ${i.isGetter} ${i.isSetter} ${i.typeArguments}',
    );
    return 5;
  }
}

class B implements Comparable<B> {
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

abstract class I {
  int f(int a, {String b});
  int get g;
  set s(int v);
  T h<T>(T t);
}

class C implements I {
  noSuchMethod(i) {
    print(i.memberName);
    return 7;
  }
}

void main() {
  dynamic a = A();
  print(a.foo(1, x: 2));
  // expect: Symbol("foo") [1] {Symbol("x"): 2} true false false []
  // expect: 5
  print(a.bar);
  // expect: Symbol("bar") [] {} false true false []
  // expect: 5
  a.baz = 3; // expect: Symbol("baz=") [3] {} false false true []
  print(a + 1);
  // expect: Symbol("+") [1] {} true false false []
  // expect: 5
  print(a[0]);
  // expect: Symbol("[]") [0] {} true false false []
  // expect: 5
  print(a());
  // expect: Symbol("call") [] {} true false false []
  // expect: 5
  I c = C();
  print(c.f(1, b: 'x'));
  // expect: Symbol("f")
  // expect: 7
  print(c.g);
  // expect: Symbol("g")
  // expect: 7
  c.s = 4; // expect: Symbol("s=")
  print(c.h<int>(1));
  // expect: Symbol("h")
  // expect: 7
  dynamic b = B();
  try {
    b.compareTo(b);
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'B' has no instance method 'compareTo' with matching arguments.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: compareTo(Instance of 'B')
  // expect: Found: compareTo(B) => int
  dynamic n;
  try {
    n.foo(1, y: 2);
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: The method 'foo' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: foo(1, y: 2)
  dynamic i = 5;
  try {
    i.foo;
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'int' has no instance getter 'foo'.
  // expect: Receiver: 5
  // expect: Tried calling: foo
  try {
    i.foo = 1;
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'int' has no instance setter 'foo='.
  // expect: Receiver: 5
  // expect: Tried calling: foo=1
  try {
    i.abs(1, 2);
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'int' has no instance method 'abs' with matching arguments.
  // expect: Receiver: 5
  // expect: Tried calling: abs(1, 2)
  // expect: Found: abs() => int
  try {
    i();
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 5
  // expect: Tried calling: call()
  dynamic f = (int x) => x;
  try {
    f();
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.<anonymous closure>'
  // expect: Receiver: Closure: (int) => int
  // expect: Tried calling: main.<anonymous closure>()
  // expect: Found: main.<anonymous closure>(int) => int
  print(#foo); // expect: Symbol("foo")
  print(#foo == Symbol('foo')); // expect: true
  print(const Symbol('a.b')); // expect: Symbol("a.b")
  print(#[]); // expect: Symbol("[]")
  print(#+); // expect: Symbol("+")
  try {
    n[1];
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: The method '[]' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: [](1)
  try {
    n + 1;
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: The method '+' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: +(1)
  try {
    i.toString(1);
  } on NoSuchMethodError catch (e) {
    print(e);
  }
  // expect: NoSuchMethodError: Class 'int' has no instance method 'toString' with matching arguments.
  // expect: Receiver: 5
  // expect: Tried calling: toString(1)
  // expect: Found: toString() => String
}
