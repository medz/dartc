import 'effects.dart' as effects;
import 'functions.dart' show pair;

int? sample(int? value, int marker) {
  effects.tick(marker);
  return value;
}

int fallback(int? a, int? b, int n) =>
    sample(a, 0) ?? sample(b, 1) ?? effects.tick(n);

int assign(int? a, int? b, int n) {
  int? local;
  local ??= sample(a, 0);
  final selected = local ??= sample(b, 1) ?? (local = effects.tick(n++));
  return selected + local + n;
}

int promoted(int? x) {
  if (x == null) return effects.tick(0);
  x += effects.tick(x);
  return x;
}

int reassigned(int? x, int? replacement) {
  if (x == null) return 0;
  effects.tick(x);
  x = replacement;
  return effects.tick(x!);
}

int sibling(int? x, bool check) {
  if (check) effects.tick(x!);
  return x ?? effects.tick(7);
}

int checked(int? x) => pair(a: sample(x, 1)!, b: effects.tick(2));

String? optional([String? value]) => value;

String? nullableDefault(int? x) => x != null ? optional('set') : optional();

num mixed(int? x) => x ?? 1.5;

Object different(int? x) => x ?? 'missing';

Never missing() => throw 'missing';

int abrupt(int? x, bool enabled) {
  if (enabled && (sample(x, 1) ?? missing()) < 2) return effects.tick(2);
  return pair(b: sample(x, 3) ?? (throw 42), a: effects.tick(4));
}

int abruptInLoop(int? x, bool stop) {
  for (var i = 0; i < 2; i++, effects.tick(x ?? missing()), effects.tick(9)) {
    if (stop) break;
    effects.tick(i);
  }
  return 5;
}
