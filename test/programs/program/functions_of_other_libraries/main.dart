import 'a.dart' as a;

part 'p.dart';

int f() => 1;

void main() {
  print(f() + a.f() + p()); // expect: 321
}
