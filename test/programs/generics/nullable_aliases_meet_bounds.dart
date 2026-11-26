// official: Dart 3.14.0 refuses the bounds with the alias (dart-lang/sdk#64958).
typedef NullableInt = int?;

class C<X, Y extends X> {}

C<NullableInt, Null>? value;
C<int?, Null>? expanded;

void main() {
  print(value); // expect: null
  print(expanded); // expect: null
}
