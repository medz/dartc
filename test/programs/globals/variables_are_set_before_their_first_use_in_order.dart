int a = trace(1);
int b = trace(2) + a;
final int c = trace(3);
int unused = trace(4);
int n() {
  number(99);
  return 5;
}

void main() {
  print('main'); // expect: main
  number(b);
  // expect: 2
  // expect: 1
  // expect: 3
  number(a); // expect: 1
  number(c);
  // expect: 3
  // expect: 3
  number(b); // expect: 3
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
