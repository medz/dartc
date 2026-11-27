import 'base.dart';

class Child extends Base {
  void _f(covariant int x) {}

  Object get own => _f;
}

void main() {
  final child = Child();
  print((
    child.inherited is void Function(Object?),
    child.own is void Function(Object?),
  )); // expect: (false, true)
}
