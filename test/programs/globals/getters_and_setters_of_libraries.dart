int _x = 1;
int get x {
  print('get');
  return _x;
}

set x(int value) {
  print('set');
  _x = value;
}

void main() {
  number(x);
  // expect: get
  // expect: 1
  x = 5; // expect: set
  number(x);
  // expect: get
  // expect: 5
  x += 2;
  // expect: get
  // expect: set
  number(x++);
  // expect: get
  // expect: set
  // expect: 7
  number(++x);
  // expect: get
  // expect: set
  // expect: 9
  number(x = 4);
  // expect: set
  // expect: 4
}

void number(int n) => print(n);
