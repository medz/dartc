class A {
  @override
  String toString() => 'A!';
}

class B {}

class C<T> {}

enum_() => 1;
void main() {
  print(1); // expect: 1
  print(-5); // expect: -5
  print(0); // expect: 0
  print(1234567890123); // expect: 1234567890123
  print(-9223372036854775808); // expect: -9223372036854775808
  print(9223372036854775807); // expect: 9223372036854775807
  print(true); // expect: true
  print(false); // expect: false
  print(null); // expect: null
  print('text'); // expect: text
  print(''); // expect:
  print(A()); // expect: A!
  print(B()); // expect: Instance of 'B'
  print(C<int>()); // expect: Instance of 'C<int>'
  print(C<C<String>>()); // expect: Instance of 'C<C<String>>'
  Object? o = 2.5;
  print(o); // expect: 2.5
  o = null;
  print(o); // expect: null
  print([null, true, 1, 2.0, 'x', A()]); // expect: [null, true, 1, 2.0, x, A!]
  print(enum_()); // expect: 1
}
