void f(Object? o) {
  if (o is! String) {
    print('no');
    return;
  }
  print(o.length);
}

void g(Object? o) {
  if (o is List<int>) {
    print(o.length);
    print(o.isEmpty ? 0 : o[0]);
  } else if (o is Map) {
    print(o.length);
  } else if (o is double) {
    print(o + 1);
  } else if (o is bool) {
    print(!o);
  } else if (o is int) {
    print(o + 1);
  } else {
    print('z');
  }
}

void main() {
  f(1); // expect: no
  f('ab'); // expect: 2
  f(true); // expect: no
  f(2.5); // expect: no
  f(null); // expect: no
  f(#a); // expect: no
  f(int); // expect: no
  f(main); // expect: no
  f((1, 2)); // expect: no
  for (final x in const [1, 'a', true]) {
    f(x);
  }
  // expect: no
  // expect: 1
  // expect: no
  g(1); // expect: 2
  g('a'); // expect: z
  g(const [4]);
  // expect: 1
  // expect: 4
  g(1.5); // expect: 2.5
  g(false); // expect: true
  g(null); // expect: z
  g(const {1: 2}); // expect: 1
  g(E.a); // expect: z
  g(const <int>[]);
  // expect: 0
  // expect: 0
}

enum E { a }
