class C {
  int f(int a, int b) => a * 10 + b;
  C me(int n) {
    number(n);
    return this;
  }
}

void main() {
  number(C().me(1).f(trace(2), trace(3)));
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 23
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
