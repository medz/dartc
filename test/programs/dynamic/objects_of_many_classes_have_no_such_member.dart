class A {}

class B {
  String toString() => 'b';
}

class C {
  void foo(int a, int b) {}
}

class D {
  void foo(String a, {int? b}) {}
}

class E extends C {}

class F {
  dynamic noSuchMethod(Invocation i) => (
    'F',
    i.memberName,
    i.positionalArguments,
    i.namedArguments,
    i.typeArguments,
  );
}

class G extends F {
  void foo() {}
}

int one(int a) => a;
int two(String a, int b) => b;
void go(Object? Function() f) {
  try {
    print(f());
  } catch (e) {
    print(e);
  }
}

void main() {
  void inner(int a, int b, int c) {}
  for (final dynamic d in [
    A(),
    B(),
    C(),
    D(),
    E(),
    F(),
    G(),
    null,
    1,
    2.5,
    'text',
    [1],
    one,
    two,
    inner,
    C().foo,
  ]) {
    go(() => d.foo(1));
    go(() => d.foo(1, c: 2));
    go(() => d.foo<int>(1));
    go(() => d.bar);
    if (d is! Function) go(() => d.bar = 1);
    go(() => d.bar());
    go(() => d());
    go(() => d<int>(1));
    go(() => d(1, 2, 3, 4));
    go(() => d[0]);
  }
  // expect: NoSuchMethodError: Class 'A' has no instance method 'foo'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'A' has no instance method 'foo'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'A' has no instance method 'foo'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'A' has no instance getter 'bar'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'A' has no instance setter 'bar='.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'A' has no instance method 'bar'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'A' has no instance method 'call'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'A' has no instance method 'call'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'A' has no instance method 'call'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'A' has no instance method '[]'.
  // expect: Receiver: Instance of 'A'
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'B' has no instance method 'foo'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'B' has no instance method 'foo'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'B' has no instance method 'foo'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'B' has no instance getter 'bar'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'B' has no instance setter 'bar='.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'B' has no instance method 'bar'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'B' has no instance method 'call'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'B' has no instance method 'call'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'B' has no instance method 'call'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'B' has no instance method '[]'.
  // expect: Receiver: Instance of 'B'
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'C' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: foo(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'C' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'C' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'C' has no instance getter 'bar'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'C' has no instance setter 'bar='.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'C' has no instance method 'bar'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'C' has no instance method 'call'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'C' has no instance method 'call'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'C' has no instance method 'call'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'C' has no instance method '[]'.
  // expect: Receiver: Instance of 'C'
  // expect: Tried calling: [](0)
  // expect: type 'int' is not a subtype of type 'String' of 'a'
  // expect: NoSuchMethodError: Class 'D' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(String, {int? b}) => void
  // expect: NoSuchMethodError: Class 'D' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(String, {int? b}) => void
  // expect: NoSuchMethodError: Class 'D' has no instance getter 'bar'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'D' has no instance setter 'bar='.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'D' has no instance method 'bar'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'D' has no instance method 'call'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'D' has no instance method 'call'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'D' has no instance method 'call'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'D' has no instance method '[]'.
  // expect: Receiver: Instance of 'D'
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'E' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: foo(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'E' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'E' has no instance method 'foo' with matching arguments.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Class 'E' has no instance getter 'bar'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'E' has no instance setter 'bar='.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'E' has no instance method 'bar'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'E' has no instance method 'call'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'E' has no instance method 'call'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'E' has no instance method 'call'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'E' has no instance method '[]'.
  // expect: Receiver: Instance of 'E'
  // expect: Tried calling: [](0)
  // expect: (F, Symbol("foo"), [1], {}, [])
  // expect: (F, Symbol("foo"), [1], {Symbol("c"): 2}, [])
  // expect: (F, Symbol("foo"), [1], {}, [int])
  // expect: (F, Symbol("bar"), [], {}, [])
  // expect: 1
  // expect: (F, Symbol("bar"), [], {}, [])
  // expect: (F, Symbol("call"), [], {}, [])
  // expect: (F, Symbol("call"), [1], {}, [int])
  // expect: (F, Symbol("call"), [1, 2, 3, 4], {}, [])
  // expect: (F, Symbol("[]"), [0], {}, [])
  // expect: (F, Symbol("foo"), [1], {}, [])
  // expect: (F, Symbol("foo"), [1], {Symbol("c"): 2}, [])
  // expect: (F, Symbol("foo"), [1], {}, [int])
  // expect: (F, Symbol("bar"), [], {}, [])
  // expect: 1
  // expect: (F, Symbol("bar"), [], {}, [])
  // expect: (F, Symbol("call"), [], {}, [])
  // expect: (F, Symbol("call"), [1], {}, [int])
  // expect: (F, Symbol("call"), [1, 2, 3, 4], {}, [])
  // expect: (F, Symbol("[]"), [0], {}, [])
  // expect: NoSuchMethodError: The method 'foo' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: The method 'foo' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: The method 'foo' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: The getter 'bar' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: The setter 'bar=' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: The method 'bar' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: The method 'call' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: The method 'call' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: The method 'call' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: The method '[]' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'int' has no instance method 'foo'.
  // expect: Receiver: 1
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'int' has no instance method 'foo'.
  // expect: Receiver: 1
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'int' has no instance method 'foo'.
  // expect: Receiver: 1
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'int' has no instance getter 'bar'.
  // expect: Receiver: 1
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'int' has no instance setter 'bar='.
  // expect: Receiver: 1
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'int' has no instance method 'bar'.
  // expect: Receiver: 1
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 1
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 1
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 1
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'int' has no instance method '[]'.
  // expect: Receiver: 1
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'double' has no instance method 'foo'.
  // expect: Receiver: 2.5
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'double' has no instance method 'foo'.
  // expect: Receiver: 2.5
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'double' has no instance method 'foo'.
  // expect: Receiver: 2.5
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'double' has no instance getter 'bar'.
  // expect: Receiver: 2.5
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'double' has no instance setter 'bar='.
  // expect: Receiver: 2.5
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'double' has no instance method 'bar'.
  // expect: Receiver: 2.5
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'double' has no instance method 'call'.
  // expect: Receiver: 2.5
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'double' has no instance method 'call'.
  // expect: Receiver: 2.5
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'double' has no instance method 'call'.
  // expect: Receiver: 2.5
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: NoSuchMethodError: Class 'double' has no instance method '[]'.
  // expect: Receiver: 2.5
  // expect: Tried calling: [](0)
  // expect: NoSuchMethodError: Class 'String' has no instance method 'foo'.
  // expect: Receiver: "text"
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'String' has no instance method 'foo'.
  // expect: Receiver: "text"
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'String' has no instance method 'foo'.
  // expect: Receiver: "text"
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'String' has no instance getter 'bar'.
  // expect: Receiver: "text"
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'String' has no instance setter 'bar='.
  // expect: Receiver: "text"
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'String' has no instance method 'bar'.
  // expect: Receiver: "text"
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'String' has no instance method 'call'.
  // expect: Receiver: "text"
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'String' has no instance method 'call'.
  // expect: Receiver: "text"
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'String' has no instance method 'call'.
  // expect: Receiver: "text"
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: t
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'foo'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: foo(1)
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'foo'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: foo(1, c: 2)
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'foo'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: foo<int>(1)
  // expect: NoSuchMethodError: Class 'List<int>' has no instance getter 'bar'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: bar
  // expect: NoSuchMethodError: Class 'List<int>' has no instance setter 'bar='.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: bar=1
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'bar'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: bar()
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'call'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: call()
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'call'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: call<int>(1)
  // expect: NoSuchMethodError: Class 'List<int>' has no instance method 'call'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: call(1, 2, 3, 4)
  // expect: 1
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: foo(1)
  // expect: Found: foo(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: bar
  // expect: Found: bar(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: bar()
  // expect: Found: bar(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'one'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: one()
  // expect: Found: one(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'one'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: one<int>(1)
  // expect: Found: one(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'one'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: one(1, 2, 3, 4)
  // expect: Found: one(int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function '[]'
  // expect: Receiver: Closure: (int) => int from Function 'one': static.
  // expect: Tried calling: [](0)
  // expect: Found: [](int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: foo(1)
  // expect: Found: foo(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: bar
  // expect: Found: bar(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: bar()
  // expect: Found: bar(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'two'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: two()
  // expect: Found: two(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'two'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: two<int>(1)
  // expect: Found: two(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'two'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: two(1, 2, 3, 4)
  // expect: Found: two(String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function '[]'
  // expect: Receiver: Closure: (String, int) => int from Function 'two': static.
  // expect: Tried calling: [](0)
  // expect: Found: [](String, int) => int
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: foo(1)
  // expect: Found: foo(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: bar
  // expect: Found: bar(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: bar()
  // expect: Found: bar(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.inner'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: main.inner()
  // expect: Found: main.inner(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.inner'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: main.inner<int>(1)
  // expect: Found: main.inner(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.inner'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: main.inner(1, 2, 3, 4)
  // expect: Found: main.inner(int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function '[]'
  // expect: Receiver: Closure: (int, int, int) => void
  // expect: Tried calling: [](0)
  // expect: Found: [](int, int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: foo(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: foo(1, c: 2)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: foo<int>(1)
  // expect: Found: foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: bar
  // expect: Found: bar(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'bar'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: bar()
  // expect: Found: bar(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'C.foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: C.foo()
  // expect: Found: C.foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'C.foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: C.foo<int>(1)
  // expect: Found: C.foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'C.foo'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: C.foo(1, 2, 3, 4)
  // expect: Found: C.foo(int, int) => void
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function '[]'
  // expect: Receiver: Closure: (int, int) => void from Function 'foo':.
  // expect: Tried calling: [](0)
  // expect: Found: [](int, int) => void
  // Only that it throws, as the text is another.
  void throws(void Function() f) {
    try {
      f();
      print('ok');
    } on NoSuchMethodError {
      print('N');
    }
  }

  for (final dynamic d in [(1, 2), (foo: 3), (foo: one)]) {
    throws(() => d.foo(1));
    throws(() => d.foo);
    throws(() => d.bar);
    throws(() => d.bar());
    throws(() => d());
  }
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: ok
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
}
