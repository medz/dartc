class A {}

class B {
  @override
  int get hashCode => 5;
  @override
  bool operator ==(Object o) => o is B;
}

int f() => 1;

class C {
  int m() => 1;
}

void show<T>(T t) {
  print(t.toString().length > 0);
  print(t.hashCode == t.hashCode);
  print(t == t);
}

void main() {
  show(1);
  // expect: true
  // expect: true
  // expect: true
  show<int?>(null);
  // expect: true
  // expect: true
  // expect: true
  show(A());
  // expect: true
  // expect: true
  // expect: true
  show(f);
  // expect: true
  // expect: true
  // expect: true
  show('x');
  // expect: true
  // expect: true
  // expect: true
  show(2.5);
  // expect: true
  // expect: true
  // expect: true
  show([1]);
  // expect: true
  // expect: true
  // expect: true
  show(null);
  // expect: true
  // expect: true
  // expect: true
  Object? o;
  print(o.toString()); // expect: null
  print(o.hashCode); // expect: 2011
  print(null.hashCode); // expect: 2011
  print(true.hashCode); // expect: 1231
  print(false.hashCode); // expect: 1237
  final a = A(), b = A();
  print(a == b); // expect: false
  print(a == a); // expect: true
  print(B() == B()); // expect: true
  print(B().hashCode); // expect: 5
  final c = C();
  print(c.m == c.m); // expect: true
  print(c.m == C().m); // expect: false
  print(c.m.hashCode == c.m.hashCode); // expect: true
  print(f == f); // expect: true
  print({c.m}.contains(c.m)); // expect: true
  print({a: 1}[b]); // expect: null
  print({a: 1}[a]); // expect: 1
  print(identical(a, a)); // expect: true
  print(identical(1, 1)); // expect: true
  print(identical(1.5, 1.5)); // expect: true
  dynamic d;
  print(d.toString()); // expect: null
  print(d.hashCode); // expect: 2011
  print(d == null); // expect: true
  d = 'abc';
  print(d.length); // expect: 3
  print(d.substring(1)); // expect: bc
  print(d[0]); // expect: a
  print(d + 'x'); // expect: abcx
  d = [1, 2];
  d.add(3);
  print(d.map((x) => x * 2).toList()); // expect: [2, 4, 6]
  d = 5;
  print(d.abs()); // expect: 5
  print(d + 2.5); // expect: 7.5
  print(d.isEven); // expect: false
  d = {'a': 1};
  print(d['a']); // expect: 1
  d['b'] = 2;
  print(d); // expect: {a: 1, b: 2}
  try {
    d.foo();
  } on NoSuchMethodError {
    print('none');
  }
  // expect: none
}
