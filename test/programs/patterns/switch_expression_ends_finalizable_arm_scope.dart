import 'dart:ffi';

class P implements Finalizable {
  final int n;
  P(this.n);
}

WeakReference<P>? weak;
List<int>? garbage;

P make() {
  final p = P(1);
  weak = WeakReference(p);
  return p;
}

bool probe() {
  garbage = List.filled(16, 0);
  return weak!.target != null;
}

bool choose(Object value) => switch (value) {
  P p => p.n == 1 && probe(),
  _ => false,
};

void main() {
  print(choose(make())); // expect: true
  print(choose(0)); // expect: false
}
