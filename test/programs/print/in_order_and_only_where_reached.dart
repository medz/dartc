void f(int n) {
  if (n == 0) return;
  print('in');
  f(n - 1);
  print('out');
}

void main() {
  f(2);
  // expect: in
  // expect: in
  // expect: out
  // expect: out
  if (1 > 2) print('never');
  print('end'); // expect: end
}
