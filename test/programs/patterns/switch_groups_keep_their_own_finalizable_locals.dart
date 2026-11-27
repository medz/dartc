import 'dart:ffi';

class P implements Finalizable {
  final int n;
  P(this.n);
}

void choose(int n) {
  switch (n) {
    case 0:
    case 1:
      late final p = P(1);
      print(p.n);
    case 2:
      late final p = P(2);
      print(p.n);
    default:
      print(3);
  }
}

void choosePattern(Object? value) {
  switch (value) {
    case 0:
      print('first');
    case P p when p.n < 0:
    case P p:
      void replace() {
        p = P(p.n + 1);
      }

      replace();
      print(p.n);
  }
}

void main() {
  choose(0); // expect: 1
  choose(1); // expect: 1
  choose(2); // expect: 2
  choose(3); // expect: 3
  choosePattern(0); // expect: first
  choosePattern(P(-1)); // expect: 0
  choosePattern(P(4)); // expect: 5
}
