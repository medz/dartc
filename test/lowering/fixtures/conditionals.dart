import 'effects.dart' as effects;
import 'functions.dart' show voidResult;

int chooseArm(bool first, bool second, int x) {
  final selected = first && effects.probe(++x)
      ? (second ? effects.tick(x++) : (x += effects.tick(2)))
      : effects.tick(--x);
  return selected * 10 + x;
}

void forward(void value) => value;

void chooseVoid(bool first, int n) =>
    forward(first ? effects.tick(n) : voidResult(n + 1));

void localVoid(bool first, int n) {
  void value = true;
  while (n < 3) {
    if (first) {
      value = voidResult(n);
    } else {
      // Exercise a legal write whose static type differs from the variable.
      // ignore: void_checks
      value = n;
    }
    if (1 < n) break;
    n++;
  }
  return value;
}
