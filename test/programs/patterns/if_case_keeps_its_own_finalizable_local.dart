import 'dart:ffi';

class P implements Finalizable {
  final int n;
  P(this.n);
}

void show(Object? value) {
  if (value case P p) {
    void replace() {
      p = P(p.n + 1);
    }

    replace();
    print(p.n);
  } else {
    print('no match');
  }
  print('after');
}

void main() {
  show(P(1));
  // expect: 2
  // expect: after
  show(null);
  // expect: no match
  // expect: after
}
