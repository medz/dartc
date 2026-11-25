class D {
  final double d;
  const D(this.d);
}

double a = -0, b = 0, c = -0.0, d = -1;
const double e = -0;
void negative(double d) {
  truth(1 / d < 0);
}

void main() {
  negative(a); // expect: true
  negative(b); // expect: false
  negative(c); // expect: true
  negative(d); // expect: true
  negative(e); // expect: true
  negative(const D(-0).d); // expect: true
  negative(const D(0).d); // expect: false
  negative(const D(e).d); // expect: true
  double x = -0;
  negative(x); // expect: true
}

void truth(bool b) => print(b);
