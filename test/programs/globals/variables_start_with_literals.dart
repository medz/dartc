int a = 3;
int b = -4;
double c = 2.5;
double d = -1;
bool e = true;

class P {
  int n = 9;
}

P? p;
P? q = null;
final int z = 6;
var v = 7;
void main() {
  number(a); // expect: 3
  number(b); // expect: -4
  truth(c == 2.5); // expect: true
  truth(d == -1.0); // expect: true
  truth(e); // expect: true
  truth(p == null); // expect: true
  truth(q == null); // expect: true
  number(z); // expect: 6
  number(v); // expect: 7
}

void number(int n) => print(n);

void truth(bool b) => print(b);
