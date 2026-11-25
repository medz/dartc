void main() {
  const a = 3, b = [1, 2];
  final f = () => a + b.last;
  print(f()); // expect: 5
  int g(int n) {
    const c = a * 2;
    return (() => c + n)();
  }

  print(g(4)); // expect: 10
  Iterable<int> h() sync* {
    const d = 5;
    yield* [1].map((x) => x + d + a);
  }

  print(h().toList()); // expect: [9]
}
