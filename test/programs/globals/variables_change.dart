int a = 3;
double d = 1.5;
bool b = false;

class P {
  int n = 9;
}

P? p;
void change() {
  a = 5;
  d = -d;
  b = !b;
  p = P();
}

void main() {
  change();
  number(a); // expect: 5
  truth(d == -1.5); // expect: true
  truth(b); // expect: true
  truth(p != null); // expect: true
  p = null;
  truth(p == null); // expect: true
  number(a = 8); // expect: 8
  number(a); // expect: 8
  number(a += 2); // expect: 10
  number(a++); // expect: 10
  number(++a); // expect: 12
  number(a--); // expect: 12
  number(a); // expect: 11
  P? x;
  number(p == null ? 1 : 0); // expect: 1
  x = p ??= P();
  truth(x == p); // expect: true
  final old = p;
  p ??= P();
  truth(p == old); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
