import 'a.dart' as a;
import 'a.dart' show A, x;

void main() {
  a.x = 3;
  a.A.s += x;
  a.A.s++;
  print((a.A.s, A.s, a.k.n, a.get)); // expect: (6, 6, 100, 3)
}
