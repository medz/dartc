int calls = 0;
int a = first();
int first() {
  a = 7;
  return 3;
}

int b = second();
int second() => ++calls == 1 ? b + 1 : 5;
void main() {
  number(a); // expect: 3
  number(b); // expect: 6
  number(calls); // expect: 2
}

void number(int n) => print(n);
