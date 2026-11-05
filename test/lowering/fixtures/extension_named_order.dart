// Named parameters intentionally appear in non-alphabetical declaration order.
extension NamedOrder on int {
  String method({int z = 2, String a = 'a'}) => '$this:$z:$a';
  static String staticMethod({int z = 2, String a = 'a'}) => '$z:$a';
  T generic<T>({int z = 2, T? a}) => (a ?? z) as T;
  String Function({int z, String a}) get extracted => method;
}

extension type NamedValue(int value) {
  new named({int z = 2, int a = 3}) : value = z * 10 + a;
  String method({int z = 2, String a = 'a'}) => '$value:$z:$a';
  static String staticMethod({int z = 2, String a = 'a'}) => '$z:$a';
  T generic<T>({int z = 2, T? a}) => (a ?? z) as T;
  String Function({int z, String a}) get extracted => method;
}

String ordinary(int x) {
  final f = x.method;
  final g = x.extracted;
  return '${x.method(z: 4)}:${f(a: 'b')}:${g(z: 5, a: 'c')}:${NamedOrder.staticMethod(a: 'd')}';
}

String extensionType(int x) {
  final v = NamedValue(x);
  final f = v.method;
  final g = v.extracted;
  return '${v.method(z: 4)}:${f(a: 'b')}:${g(z: 5, a: 'c')}:${NamedValue.staticMethod(a: 'd')}';
}

int constructors() {
  const f = NamedValue.named;
  return NamedValue.named().value +
      f(a: 4).value +
      NamedValue.named(z: 5, a: 6).value;
}

String genericMethods(int x) {
  final f = x.generic;
  final g = NamedValue(x).generic;
  return '${x.generic<int>(z: 4)}:${f<String>(a: 'ok')}:${g<int>()}:${NamedValue(x).generic<String>(a: 'yes')}';
}
