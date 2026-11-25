double d = half(3.0);
double half(double x) => x / 2;
bool b = not(true);
bool not(bool x) => !x;

class P {}

P? make(bool b) => b ? P() : null;
P? p = make(false), q = make(true);
int calls = 0;
P? none() {
  calls++;
  return null;
}

P? r = none();
void main() {
  truth(d == 1.5); // expect: true
  truth(b); // expect: false
  truth(p == null); // expect: true
  truth(q == q); // expect: true
  truth(q == null); // expect: false
  truth(r == null); // expect: true
  truth(r == null); // expect: true
  number(calls); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);
