class K {
  final int n;
  K(this.n);
}

void main() {
  print('straße ÀÉ ǆ İ ΑΣ'.toUpperCase()); // expect: STRAßE ÀÉ Ǆ İ ΑΣ
  print('ÀÉ İ ΑΣ ǅ'.toLowerCase()); // expect: àé i ασ ǆ
  print(
    Function.apply((int a, {int b = 1}) => a + b, [1], {#b: 5}),
  ); // expect: 6
  final x = Expando<String>('e');
  final k = K(1);
  x[k] = 'v';
  print(x[k]); // expect: v
  print(x[K(1)]); // expect: null
  print(x); // expect: Expando:e
  print(Iterable.generate(3, (i) => i * 2)); // expect: (0, 2, 4)
  print([1, 2].cast<num>()); // expect: [1, 2]
  print(List.castFrom<int, num>([1])); // expect: [1]
  try {
    throw StateError('x');
  } catch (e, s) {
    print(s is StackTrace);
    print((e as Error).stackTrace != null);
  }
  // expect: true
  // expect: true
  print(StackTrace.current is StackTrace); // expect: true
  print(identityHashCode(k) == identityHashCode(k)); // expect: true
  print(Error.safeToString('x\n')); // expect: "\"x\\n\""
  print(Comparable.compare(1, 2)); // expect: -1
  print(['b', 'a']..sort()); // expect: [a, b]
  print(const int.fromEnvironment('zz', defaultValue: 3)); // expect: 3
  print(const String.fromEnvironment('q')); // expect:
  print(WeakReference(k).target == k); // expect: true
  Enum? e;
  print(e); // expect: null
  print(Symbol('a')); // expect: Symbol("a")
}
