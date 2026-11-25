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
}
