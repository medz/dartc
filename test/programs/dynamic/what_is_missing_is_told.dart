abstract class I {
  int f(int a, [int b = 7, int? c]);
  void g({int x = 3, String? y});
  List<T> h<T extends num>(T t);
  int get p;
  set p(int v);
  int operator +(int o);
}

class C implements I {
  noSuchMethod(Invocation i) {
    print(
      '${i.memberName} ${i.positionalArguments} ${i.namedArguments} ${i.typeArguments}',
    );
    return i.memberName == #h ? <int>[] : 1;
  }
}

class D extends C {
  int f(int a, [int b = 9, int? c]);
}

class E implements I {
  noSuchMethod(i) => 'wrong';
}

int top(int a, {int b = 1}) => a;

class K {
  int m(int a) => a;
  int get gt => 1;
  final fi = 2;
  static int st() => 1;
}

void go(Function() f) {
  try {
    print(f());
  } catch (e) {
    print(e);
  }
}

void main() {
  final I c = C();
  c.f(1); // expect: Symbol("f") [1, 7, null] {} []
  c.f(1, 2, 3); // expect: Symbol("f") [1, 2, 3] {} []
  c.g(); // expect: Symbol("g") [] {Symbol("x"): 3, Symbol("y"): null} []
  c.g(y: 'q'); // expect: Symbol("g") [] {Symbol("x"): 3, Symbol("y"): q} []
  c.h(5); // expect: Symbol("h") [5] {} [int]
  c.h<num>(5); // expect: Symbol("h") [5] {} [num]
  c.p; // expect: Symbol("p") [] {} []
  c.p = 4; // expect: Symbol("p=") [4] {} []
  c + 2; // expect: Symbol("+") [2] {} []
  I d = D();
  d.f(8); // expect: Symbol("f") [8, 7, null] {} []
  go(
    () => (E() as I).f(1),
  ); // expect: type 'String' is not a subtype of type 'int'
  final t = c.f;
  t(5); // expect: Symbol("f") [5, 7, null] {} []
  print(t); // expect: Closure: (int, [int, int?]) => int from Function 'f':.
  dynamic k = K();
  go(() => k.m());
  // expect: NoSuchMethodError: Class 'K' has no instance method 'm' with matching arguments.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: m()
  // expect: Found: m(int) => int
  go(() => k.m(1, 2));
  // expect: NoSuchMethodError: Class 'K' has no instance method 'm' with matching arguments.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: m(1, 2)
  // expect: Found: m(int) => int
  go(() => k.m(a: 1));
  // expect: NoSuchMethodError: Class 'K' has no instance method 'm' with matching arguments.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: m(a: 1)
  // expect: Found: m(int) => int
  go(() => k.gt = 1);
  // expect: NoSuchMethodError: Class 'K' has no instance setter 'gt='.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: gt=1
  go(() => k.fi = 1);
  // expect: NoSuchMethodError: Class 'K' has no instance setter 'fi='.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: fi=1
  go(() => k.gt(3));
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 1
  // expect: Tried calling: call(3)
  go(() => k.zz(1, q: 2));
  // expect: NoSuchMethodError: Class 'K' has no instance method 'zz'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: zz(1, q: 2)
  go(() => k.zz);
  // expect: NoSuchMethodError: Class 'K' has no instance getter 'zz'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: zz
  go(() => k.zz = 5);
  // expect: NoSuchMethodError: Class 'K' has no instance setter 'zz='.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: zz=5
  go(() => k[1]);
  // expect: NoSuchMethodError: Class 'K' has no instance method '[]'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: [](1)
  go(() => k + 1);
  // expect: NoSuchMethodError: Class 'K' has no instance method '+'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: +(1)
  go(() => -k);
  // expect: NoSuchMethodError: Class 'K' has no instance method 'unary-'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: unary-()
  go(() => k());
  // expect: NoSuchMethodError: Class 'K' has no instance method 'call'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: call()
  go(() => k < 1);
  // expect: NoSuchMethodError: Class 'K' has no instance method '<'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: <(1)
  go(() => k[1] = 2);
  // expect: NoSuchMethodError: Class 'K' has no instance method '[]='.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: []=(1, 2)
  dynamic f = top;
  go(() => f());
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'top'
  // expect: Receiver: Closure: (int, {int b}) => int from Function 'top': static.
  // expect: Tried calling: top()
  // expect: Found: top(int, {int b}) => int
  go(() => f(1, 2));
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'top'
  // expect: Receiver: Closure: (int, {int b}) => int from Function 'top': static.
  // expect: Tried calling: top(1, 2)
  // expect: Found: top(int, {int b}) => int
  go(() => f(1, c: 2));
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'top'
  // expect: Receiver: Closure: (int, {int b}) => int from Function 'top': static.
  // expect: Tried calling: top(1, c: 2)
  // expect: Found: top(int, {int b}) => int
  dynamic m = K().m;
  go(() => m());
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'K.m'
  // expect: Receiver: Closure: (int) => int from Function 'm':.
  // expect: Tried calling: K.m()
  // expect: Found: K.m(int) => int
  dynamic n;
  go(() => n());
  // expect: NoSuchMethodError: The method 'call' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: call()
  go(() => n.x = 1);
  // expect: NoSuchMethodError: The setter 'x=' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: x=1
  go(() => n[0] = 1);
  // expect: NoSuchMethodError: The method '[]=' was called on null.
  // expect: Receiver: null
  // expect: Tried calling: []=(0, 1)
  go(() => n.toString(1));
  // expect: NoSuchMethodError: The null object does not have a method 'toString' with matching arguments.
  // expect: Receiver: null
  // expect: Tried calling: toString(1)
  // expect: Found: toString() => String
  go(() => f.foo);
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'foo'
  // expect: Receiver: Closure: (int, {int b}) => int from Function 'top': static.
  // expect: Tried calling: foo
  // expect: Found: foo(int, {int b}) => int
  dynamic s = 'x';
  go(() => s.length(1));
  // expect: NoSuchMethodError: Class 'int' has no instance method 'call'.
  // expect: Receiver: 1
  // expect: Tried calling: call(1)
  go(() => s.foo());
  // expect: NoSuchMethodError: Class 'String' has no instance method 'foo'.
  // expect: Receiver: "x"
  // expect: Tried calling: foo()
  dynamic l = [1];
  go(() => l.foo);
  // expect: NoSuchMethodError: Class 'List<int>' has no instance getter 'foo'.
  // expect: Receiver: Instance(length:1) of '_GrowableList'
  // expect: Tried calling: foo
  dynamic ty = int;
  go(() => ty());
  // expect: NoSuchMethodError: Attempted to use type 'int' as a function. Since types do not define a method 'call', this is not possible. Did you intend to call the int constructor and forget the 'new' operator?
  // expect: Receiver: int
  // expect: Tried calling: int()
  dynamic ctor = K.new;
  go(() => ctor(1));
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'K.K'
  // expect: Receiver: Closure: () => K from Function 'K.': static.
  // expect: Tried calling: K.K(1)
  // expect: Found: K.K() => K
  Function ff = top;
  go(() => ff());
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'top'
  // expect: Receiver: Closure: (int, {int b}) => int from Function 'top': static.
  // expect: Tried calling: top()
  // expect: Found: top(int, {int b}) => int
  go(() => k.hashCode = 1);
  // expect: NoSuchMethodError: Class 'K' has no instance setter 'hashCode='.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: hashCode=1
  go(() => k._priv);
  // expect: NoSuchMethodError: Class 'K' has no instance getter '_priv'.
  // expect: Receiver: Instance of 'K'
  // expect: Tried calling: _priv
  dynamic lf = (int a) {
    return a;
  };
  go(() => lf());
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.<anonymous closure>'
  // expect: Receiver: Closure: (int) => int
  // expect: Tried calling: main.<anonymous closure>()
  // expect: Found: main.<anonymous closure>(int) => int
  int loc(String z) => 1;
  dynamic ll = loc;
  go(() => ll(1, 2));
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'main.loc'
  // expect: Receiver: Closure: (String) => int
  // expect: Tried calling: main.loc(1, 2)
  // expect: Found: main.loc(String) => int
}
