import 'effects.dart' as effects;
import 'scalar_constants.dart' as constants;

const offset = constants.stride + 3;

int positional(int a, [int b = offset, bool add = true]) => add ? a + b : a - b;

int named({required int a, int b = constants.stride, int c = 2}) =>
    a * 100 + b * 10 + c;

int callDefaults(bool full, int n) {
  const scale = offset * 2;
  final first = full
      ? positional(effects.tick(n), effects.tick(n + 1), false)
      : positional(effects.tick(n));
  return first * scale +
      named(c: effects.tick(n + 2), a: effects.tick(n + 3)) +
      constants.stride;
}

String text([String value = constants.label]) => value;

String pickText(bool useDefault) => useDefault
    ? text()
    : text(
        'line\n'
        r'\u0041',
      );

double number([double value = -0.0]) => value;

double pickNumber(int n) => n < 0 ? number() : (n < 1 ? -0 : number(8));

int minInt() => -9223372036854775808;

void maybe([void value]) => value;

void pickNull(bool explicit) => explicit ? maybe(null) : maybe();

Null fallthrough() {}
