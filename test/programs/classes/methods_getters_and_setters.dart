class T {
  double c = 0;
  double get f => c * 1.8 + 32;
  set f(double v) => c = (v - 32) / 1.8;
}

class Counter {
  int _n = 0;
  int get next => ++_n;
  set _raw(int v) {
    _n = v;
  }

  void reset() {
    _raw = 10;
  }
}

void main() {
  final t = T();
  t.f = 212;
  truth(t.c == 100); // expect: true
  t.f += 18;
  truth(t.c == 110); // expect: true
  final c = Counter();
  number(c.next); // expect: 1
  number(c.next); // expect: 2
  c.reset();
  number(c.next); // expect: 11
}

void number(int n) => print(n);

void truth(bool b) => print(b);
