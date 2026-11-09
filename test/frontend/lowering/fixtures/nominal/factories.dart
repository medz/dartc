import '../effects.dart' as effects;

abstract class Ticket() {
  factory named(int n, {int? x, int? y}) = Middle.pass;
  factory positional([int? n]) = Product.pos;
  int get score;
}

abstract class Middle() implements Ticket {
  factory pass(int n, {int? y, int? x}) = Product.build;
}

class Product._(final int _score) implements Middle {
  @override
  int get score => _score;

  factory build(int n, {int? y = 3, int? x = 4, int bonus = 9}) =>
      Product._(effects.tick(n) + (x ?? 0) * 100 + (y ?? 0) * 10 + bonus);
  new pos([int? n = 7, int extra = 2]) : this._((n ?? 0) * 10 + extra);
}

int redirected(int mode, int n) {
  final ticket = switch (mode) {
    0 => Ticket.named(n),
    1 => Ticket.named(n, x: null),
    2 => Ticket.named(y: effects.tick(1), effects.tick(n), x: effects.tick(2)),
    3 => Ticket.positional(),
    4 => Ticket.positional(null),
    _ => Ticket.positional(n),
  };
  return ticket.score;
}
