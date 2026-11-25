class A {
  final int n;
  final A? next;
  const A(this.n, [this.next]);
}

class B extends A {
  const B(int n) : super(n);
}

class D {
  final double d;
  const D(this.d);
}

const k = A(1);

class S {
  static const A one = A(1);
}

void main() {
  truth(identical(const A(1), k)); // expect: true
  truth(identical(k, S.one)); // expect: true
  truth(identical(const A(1), const A(2))); // expect: false
  truth(identical(const A(1), A(1))); // expect: false
  truth(identical(const A(1), const B(1))); // expect: false
  truth(identical(const A(1, A(2)), const A(1, A(2)))); // expect: true
  truth(identical(const A(1, A(2)), const A(1, B(2)))); // expect: false
  truth(identical(const D(0.0), const D(-0.0))); // expect: false
  truth(identical(const D(0.0 / 0.0), const D(0.0 / 0.0))); // expect: true
  truth(identical(const D(1), const D(1.0))); // expect: true
  const local = A(1);
  truth(identical(local, k)); // expect: true
}

void truth(bool b) => print(b);
