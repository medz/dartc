class G<X> {
  external X f;
  external void m(X x);
  external set s(X x);
  external void c(covariant num x);
  external static void st(int x);
}

class H extends G<String> {}

external void top(int x);
external void gen<T extends num>(T x);
void main() {
  G<Object> g = H();
  for (final use in <Function>[
    () => g.f = 1,
    () => g.m(1),
    () => g.s = 1,
    () => (g as dynamic).f = 1,
    () => (g as dynamic).m(1),
    () => (g as dynamic).s = 1,
    () => (g as dynamic).c('a'),
    () => g.m,
    () => (g.m as dynamic)(1),
    () => (G.st as dynamic)('a'),
    () => (top as dynamic)('a'),
    () => (gen as dynamic)('a'),
    () => (gen as dynamic)<String>('a'),
    () => (top as dynamic)(),
  ]) {
    try {
      print(use());
    } catch (e) {
      print('$e'.split('\n').first);
    }
  }
  // expect: NoSuchMethodError: No static setter 'f=' declared in class 'G<dynamic>'.
  // expect: type 'int' is not a subtype of type 'String' of 'x'
  // expect: type 'int' is not a subtype of type 'String' of 'x'
  // expect: type 'int' is not a subtype of type 'String' of '#externalFieldValue'
  // expect: type 'int' is not a subtype of type 'String' of 'x'
  // expect: type 'int' is not a subtype of type 'String' of 'x'
  // expect: type 'String' is not a subtype of type 'num' of 'x'
  // expect: Closure: (Object?) => void from Function 'm':.
  // expect: type 'int' is not a subtype of type 'String' of 'x'
  // expect: type 'String' is not a subtype of type 'int' of 'x'
  // expect: type 'String' is not a subtype of type 'int' of 'x'
  // expect: type 'String' is not a subtype of type 'num' of 'x'
  // expect: type 'String' is not a subtype of type 'num' of 'T'
  // expect: NoSuchMethodError: Closure call with mismatched arguments: function 'top'
}
