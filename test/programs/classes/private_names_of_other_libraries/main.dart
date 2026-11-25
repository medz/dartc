import 'a.dart';

class B extends A {
  int _f() => 2;
  int g() => _f();
}

void main() {
  print((B().f(), B().g(), make().n)); // expect: (1, 2, 4)
}
