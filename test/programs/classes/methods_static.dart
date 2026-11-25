class M {
  static int twice(int x) => x * 2;
  static const k = 7;
  int use() => twice(k) + M.twice(1);
}

void main() {
  number(M.twice(4)); // expect: 8
  number(M().use()); // expect: 16
  number(M.k); // expect: 7
}

void number(int n) => print(n);
