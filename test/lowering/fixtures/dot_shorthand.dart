import 'effects.dart' as effects;

class Point(final int value) {
  new named(int x, {int y = 2}) : this(x + y);
  factory create(int x) => Point(effects.tick(x));
  static Point make(int x, {int y = 3}) => Point(effects.tick(x) + y);
}

int shorthand(int n, int mode) {
  try {
    final Point point = switch (mode) {
      0 => .new(effects.tick(n)),
      1 => .named(effects.tick(n), y: effects.tick(4)),
      2 => .create(effects.tick(n)),
      _ => .make(effects.tick(n), y: effects.tick(5)),
    };
    return point.value;
  } catch (_) {
    return -1;
  }
}
