import 'effects.dart' as effects;

int swap(int a, int b) {
  final value = ((a, b) = (effects.tick(b), effects.tick(a)));
  return value.$1 * 1000 + value.$2 * 100 + a * 10 + b;
}

int namedBindings(int n) {
  final (z: (first, last), :sign) = (sign: n < 0, z: (n, n + 3));
  if (sign) return last - first;
  return first + last;
}

int loopBindings(int n) {
  var sum = 0;
  for (var (i, step) = (0, 1); i < n; (i, step) = (i + step, step + 1)) {
    sum += effects.tick(i);
  }
  return sum;
}

int chooseField(int a, int b, int n) {
  final Object subject = (effects.tick(a), effects.tick(b));
  return switch (subject) {
    (0, int v) || (int v, 0) when effects.tick(++n) < 4 => v + n,
    (_, _) => effects.tick(n),
    _ => 12,
  };
}

int patternOrder(bool zFirst, Object? value) {
  final Object subject = (z: value, a: 1);
  if (zFirst) {
    if (subject case (z: (var s as String), a: 0)) return s == 'x' ? 1 : 2;
  } else {
    if (subject case (a: 0, z: (var s as String))) return s == 'x' ? 3 : 4;
  }
  return effects.tick(8);
}

int exhaustivePair(bool a, bool? b) {
  switch ((a, b)) {
    case (true, _):
      return 1;
    case (false, true):
      return 2;
    case (false, false):
    case (false, null):
      return 3;
  }
}

int matchShape(int kind, Object? n) {
  final Object? value = switch (kind) {
    0 => (a: n),
    1 => (n,),
    2 => (),
    _ => n,
  };
  return switch (value) {
    const (a: 3) => 13,
    (a: int v) => v + 1,
    (var v,) when v is int => v + 2,
    () => 30,
    _ => 40,
  };
}
