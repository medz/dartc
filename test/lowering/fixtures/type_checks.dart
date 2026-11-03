import 'effects.dart' as effects;
import 'functions.dart' show pair;

Object? observe(Object? x, int tag) {
  effects.tick(tag);
  return x;
}

int classify(Object? x) {
  final value = observe(x, 0);
  if (value is int) return value + effects.tick(1);
  if (value is String?) return effects.tick(2);
  if (value is! num) return effects.tick(3);
  return effects.tick(4);
}

int nestedTest(Object? x) {
  if (x == null) return 0;
  if (x is num) {
    if (x is! int) return effects.tick(1);
    return x + effects.tick(2);
  }
  return effects.tick(3);
}

int castBeforeCall(Object? x) =>
    pair(b: observe(x, 1) as int, a: effects.tick(2));

Object? nullableCast(Object? x, bool string) =>
    string ? observe(x, 1) as String? : observe(x, 2) as num?;

Never impossible(Object? x) => x as Never;
