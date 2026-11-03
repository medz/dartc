import 'effects.dart' as effects;
import 'type_checks.dart' show observe;

int shared(Object? x, int n) {
  switch (observe(x, 0)) {
    case int v when effects.tick(++n) < v:
    case int v when v < effects.tick(++n):
      if (n < 3) v += effects.tick(1);
      n += effects.tick(v);
    case String s when s == 'hit' && effects.probe(++n):
    case bool b when b && effects.probe(++n):
      n += effects.tick(8);
    default:
      n += effects.tick(9);
  }
  return n;
}

int labels(int x, bool stop) {
  var i = 0;
  done:
  switch (effects.tick(x)) {
    back:
    case 9 when false:
      i += effects.tick(1);
      if (stop) break done;
      continue forward;
    forward:
    case 1 when effects.probe(8):
    case 2:
      switch (i) {
        case 0:
          continue back;
        default:
          i += effects.tick(3);
      }
    default:
      continue back;
  }
  return i;
}

int partial(int x) {
  switch (effects.tick(x)) {
    case 1:
      return 6;
    case 2:
      break;
    case 3:
    case 4:
  }
  return x + 1;
}

int allFlags(bool? x) {
  switch (x) {
    case true:
      return 4;
    case false:
      return 5;
    case null:
      return 6;
  }
}

int allNumbers(num x) {
  switch (x) {
    case int i:
      return i;
    case double _:
      return 7;
  }
}
