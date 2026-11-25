class C {
  int n = 1;
  double d = 1;
  C? c;
  C get self {
    print('self');
    return this;
  }
}

void main() {
  final c = C();
  number(c.n = 5); // expect: 5
  number(c.n += 2); // expect: 7
  number(c.n++); // expect: 7
  number(++c.n); // expect: 9
  number(c.n--); // expect: 9
  number(--c.n); // expect: 7
  c.n *= 3;
  c.n ~/= 2;
  number(c.n); // expect: 10
  c.d /= 4;
  truth(c.d == 0.25); // expect: true
  c.self.n += 10; // expect: self
  number(c.n); // expect: 20
  c.self.n++; // expect: self
  number(c.n); // expect: 21
  c.c ??= C();
  c.c ??= c;
  truth(c.c == c); // expect: false
  final other = c.c ?? c;
  truth(other == c); // expect: false
}

void number(int n) => print(n);

void truth(bool b) => print(b);
