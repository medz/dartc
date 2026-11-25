class E {
  final int v;
  E(this.v);
  @override
  bool operator ==(Object o) {
    print('eq');
    return identical(this, o) || v == 9;
  }

  @override
  int get hashCode => v;
}

class F extends E {
  F() : super(9);
  @override
  bool operator ==(Object o) => super == o;
}

class P {}

void main() {
  E? n;
  final e = E(1), f = E(1), nine = E(9);
  P? p;
  final q = P();
  truth(n == null); // expect: true
  truth(null == n); // expect: true
  truth(n == e); // expect: false
  truth(e == n); // expect: false
  truth(e == e);
  // expect: eq
  // expect: true
  truth(e == f);
  // expect: eq
  // expect: false
  truth(e != f);
  // expect: eq
  // expect: true
  truth(nine == f);
  // expect: eq
  // expect: true
  truth(F() == e);
  // expect: eq
  // expect: true
  truth(n != null); // expect: false
  truth(p == q); // expect: false
  truth(q == q); // expect: true
  truth(q != p); // expect: true
  truth(p == null); // expect: true
  truth(identical(e, f)); // expect: false
  truth(identical(e, e)); // expect: true
  truth(identical(n, null)); // expect: true
  Object o = e, r = q;
  truth(o == f);
  // expect: eq
  // expect: false
  truth(r == q); // expect: true
  truth(r == o); // expect: false
  number(e.hashCode); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);
