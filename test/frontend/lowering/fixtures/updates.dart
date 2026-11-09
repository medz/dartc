import 'effects.dart' as effects;
import 'functions.dart' show pair;

int readAndWrite(int x) {
  final old = x++;
  final next = --x;
  final sum = x += (x = old + 3);
  final product = x *= ++x;
  final difference = x -= x--;
  return old + next + sum + product + difference + x;
}

int argumentWrites(int x) =>
    pair(b: effects.tick(x++), a: effects.tick(++x)) + x;

int shortCircuitWrites(bool first, bool second, int x) {
  var y = 0;
  if ((first || (y = effects.tick(x++)) < 3) &&
      (second || (x += effects.tick(y + 1)) < 6)) {
    y += x;
  }
  return pair(a: x, b: y);
}

int knownGuards(bool enabled, int x) {
  final skipped = (enabled = false) && effects.probe(x++);
  if (skipped || (enabled = true) && effects.probe(x++)) return x;
  return x + 1;
}

int loopWrites(int limit) {
  var i = 0;
  var sum = 0;
  var active = true;
  while ((active = i++ < limit) && (sum += effects.tick(i)) < 7) {
    sum += i;
  }
  if (active) return sum * 10 + i;
  return i;
}
