class V {
  final int x;
  V(this.x);
  V operator +(V o) => V(x + o.x);
  V operator -(V o) => V(x - o.x);
  V operator -() => V(-x);
  V operator ~() => V(x * 100);
  bool operator <(V o) => x < o.x;
  int operator [](int i) => x + i;
  void operator []=(int i, int v) {
    number(i);
    number(v);
  }
}

void main() {
  final a = V(1);
  var b = V(5);
  number((a + b).x); // expect: 6
  number((a - b).x); // expect: -4
  number((-a).x); // expect: -1
  number((~a).x); // expect: 100
  truth(a < b); // expect: true
  number(a[3]); // expect: 4
  a[trace(2)] = trace(9);
  // expect: 2
  // expect: 9
  // expect: 2
  // expect: 9
  a[2] += 5;
  // expect: 2
  // expect: 8
  a[1]++;
  // expect: 1
  // expect: 3
  number(a[4] = 6);
  // expect: 4
  // expect: 6
  // expect: 6
  number(++a[0]);
  // expect: 0
  // expect: 2
  // expect: 2
  b += a;
  number(b.x); // expect: 6
  b -= a;
  number(b.x); // expect: 5
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
