int a = trace(1), b = trace(2);
void main() {
  a = 5;
  number(a); // expect: 5
  b += 10; // expect: 2
  number(b); // expect: 12
  b++;
  number(b); // expect: 13
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
