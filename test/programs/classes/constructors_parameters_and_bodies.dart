class C {
  int n;
  C(int n) : n = n * 2 {
    n += 100;
    this.n += n;
    number(n);
    if (n > 150) return;
    print('end');
  }
  C.assign(int m) : n = 0 {
    n = m;
  }
}

void main() {
  number(C(3).n);
  // expect: 103
  // expect: end
  // expect: 109
  number(C(60).n);
  // expect: 160
  // expect: 280
  number(C.assign(4).n); // expect: 4
}

void number(int n) => print(n);
