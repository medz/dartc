import 'effects.dart';

class Box<T>(final T value, {int marker = 0}) {
  this {
    tick(marker);
  }
  factory redirect(T value, {int marker}) = Box<T>;
  static Box<U> make<U>(U value, {int marker = 0}) =>
      Box<U>(value, marker: marker);
}

int forms(dynamic value, int form) {
  final Box<int> box = switch (form) {
    0 => .new(value, marker: tick(2)),
    1 => Box<int>(value, marker: tick(2)),
    2 => .redirect(value, marker: tick(2)),
    3 => Box<int>.redirect(value, marker: tick(2)),
    4 => .make<int>(value, marker: tick(2)),
    _ => Box.make<int>(value, marker: tick(2)),
  };
  return box.value;
}
