class C {
  int n = 0;
  C get c {
    print('get');
    return this;
  }

  set s(int v) {
    print('set');
    number(v);
  }

  int get s {
    print('gets');
    return 1;
  }

  int operator [](int i) {
    print('index');
    return i;
  }

  void operator []=(int i, int v) {
    print('store');
    number(i);
    number(v);
  }
}

C make(int n) {
  number(n);
  return C();
}

void main() {
  make(1).c.s = trace(2);
  // expect: 1
  // expect: get
  // expect: 2
  // expect: set
  // expect: 2
  make(3).s += trace(4);
  // expect: 3
  // expect: gets
  // expect: 4
  // expect: set
  // expect: 5
  make(5)[trace(6)] = trace(7);
  // expect: 5
  // expect: 6
  // expect: 7
  // expect: store
  // expect: 6
  // expect: 7
  make(8).c[trace(9)] += trace(10);
  // expect: 8
  // expect: get
  // expect: 9
  // expect: index
  // expect: 10
  // expect: store
  // expect: 9
  // expect: 19
  number(make(11)[trace(12)]++);
  // expect: 11
  // expect: 12
  // expect: index
  // expect: store
  // expect: 12
  // expect: 13
  // expect: 12
  number(make(13).s++);
  // expect: 13
  // expect: gets
  // expect: set
  // expect: 2
  // expect: 1
  var x = 1;
  x = x + (x = 5) + x;
  number(x); // expect: 11
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
