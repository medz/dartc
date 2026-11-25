extension D<T> on int {
  Type get type => T;
  Type m() => T;
  set s(Type t) => print((T, t));
  Type operator [](int i) => T;
  void all() {
    print(type);
    print(this.type);
    print(1.type);
    print((this).type);
    print(m());
    print(this.m());
    print(2.m());
    s = int;
    this.s = int;
    3.s = int;
    print(this[0]);
    print(3[0]);
    print(D<bool>(this).type);
    print(D(this).type);
    final f = m, g = this.m, h = 1.m;
    print((f(), g(), h()));
    final me = this;
    print(me.type);
    void local() => print((type, this.type));
    local();
    print([1].map((x) => x.type));
    print(this + 1);
    1
      ..type
      ..s = String;
    this..s = String;
  }
}

class K {}

extension O<T> on K {
  K operator +(int n) {
    print((T, n));
    return this;
  }

  K operator -() {
    print((T, '-'));
    return this;
  }

  K get own => this;
  set own(K k) => print((T, 'own'));

  void all() {
    var k = K();
    k += 1;
    k++;
    -k;
    own += 2;
    own++;
    this.own += 3;
    final self = this;
    self + 4;
    this + 5;
  }
}

void main() {
  D<String>(0).all();
  // expect: String
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: String
  // expect: dynamic
  // expect: dynamic
  // expect: (String, int)
  // expect: (dynamic, int)
  // expect: (dynamic, int)
  // expect: dynamic
  // expect: dynamic
  // expect: bool
  // expect: dynamic
  // expect: (String, dynamic, dynamic)
  // expect: dynamic
  // expect: (String, dynamic)
  // expect: (dynamic)
  // expect: 1
  // expect: (dynamic, String)
  // expect: (dynamic, String)
  0.all();
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: dynamic
  // expect: (dynamic, int)
  // expect: (dynamic, int)
  // expect: (dynamic, int)
  // expect: dynamic
  // expect: dynamic
  // expect: bool
  // expect: dynamic
  // expect: (dynamic, dynamic, dynamic)
  // expect: dynamic
  // expect: (dynamic, dynamic)
  // expect: (dynamic)
  // expect: 1
  // expect: (dynamic, String)
  // expect: (dynamic, String)
  O<bool>(K()).all();
  // expect: (dynamic, 1)
  // expect: (dynamic, 1)
  // expect: (dynamic, -)
  // expect: (dynamic, 2)
  // expect: (bool, own)
  // expect: (dynamic, 1)
  // expect: (bool, own)
  // expect: (dynamic, 3)
  // expect: (dynamic, own)
  // expect: (dynamic, 4)
  // expect: (dynamic, 5)
  var k = K();
  k += 6; // expect: (dynamic, 6)
  ++k; // expect: (dynamic, 1)
  -k; // expect: (dynamic, -)
}
