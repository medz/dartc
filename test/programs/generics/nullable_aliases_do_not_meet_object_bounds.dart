typedef NullableInt = int?;

extension type E<X extends Object>(X value) {}

void main() {
  final e = null as E<NullableInt>; // error 23: 'NullableInt' doesn't conform to the bound 'Object' of the type parameter 'X'.
  print(e);
}
