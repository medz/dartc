bool f(int n) {
  Object x = n;
  return x is int;
}

Type g(int n) => (n as Object).runtimeType;
