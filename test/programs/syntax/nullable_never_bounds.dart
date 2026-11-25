Object fallback<T extends Never>(T? x) => x ?? 'fallback';

Object throughBound<T extends Never, U extends T?>(U x) => x ?? 'bound';

void main() {
  print(fallback<Never>(null)); // expect: fallback
  print(throughBound<Never, Null>(null)); // expect: bound
}
