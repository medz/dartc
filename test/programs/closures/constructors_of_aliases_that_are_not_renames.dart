class C<T> {}

typedef Alias<X, Y> = C<X>;
typedef Narrow<X extends num> = C<X>;
typedef Rename<X> = C<X>;

void main() {
  const make = Alias.new;
  final Object value = make;

  print(value is C<X> Function<X, Y>()); // expect: true
  final specializedLater = make<int, String>;
  print(specializedLater == C<int>.new); // expect: false
  print(identical(Alias<int, String>.new, C<int>.new)); // expect: true
  print(Alias<int, String>.new == C<int>.new); // expect: true
  final Object narrow = Narrow.new;
  print((narrow is C<T> Function<T extends num>(), Narrow.new == C.new)); // expect: (true, false)
  print(Rename.new == C.new); // expect: true
  print(identical(Rename.new, C.new)); // expect: true
  print(make<int, String>() is C<int>); // expect: true
  final n = Narrow.new;
  print(n<int>().runtimeType); // expect: C<int>
}
