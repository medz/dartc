import 'effects.dart' as effects;
import 'type_checks.dart' show observe;

int matchCases(Object? x, int n) => switch (observe(x, 0)) {
  null => effects.tick(n),
  1 || 2 => effects.tick(2),
  int v when effects.tick(++n) < 3 => v + n,
  int v => v - n,
  'yes' => n + 7,
  _ => n,
};

int matchIf(Object? x, int n) {
  if (observe(x, 0) case ((int v && >= 2) || (int v && <= 0))
      when effects.tick(++n) < 3) {
    if (n <= 1) v += effects.tick(2);
    return v + n;
  } else {
    return effects.tick(n);
  }
}

int checkedPattern(Object? x) => switch (observe(x, 0)) {
  (int n)? => effects.tick(n),
  (var s as String)! => s == 'yes' ? 1 : 2,
};

int exhaustive(bool? flag) => switch (flag) {
  true => 1,
  false => 2,
  null => 3,
};

int alternatives(Object? x) {
  if (x case int _ || String _) {
    return x is int ? x + 1 : 7;
  }
  return 0;
}

Never throwCase(bool flag) => switch (flag) {
  true => throw 11,
  false => throw 12,
};
