// ignore_for_file: unnecessary_type_check
import 'effects.dart';

extension type const Pair<A, B>((A, B) values) {
  new fields(A left, B right) : values = (left, right);
  factory describe(A left, B right) => Pair((left, right))..trace();

  void trace() {
    tick(A == int ? 1 : 2);
    tick(B == String ? 3 : 4);
  }
}

extension type const Number(int value);
extension type const Box<T>(T value);

typedef Flip<X, Y> = Pair<Y, X>;
typedef Fixed<T> = Pair<int, T>;
typedef Repeated<T> = Pair<T, T>;
typedef Proper<X, Y> = Pair<X, Y>;
typedef Phantom<T> = Number;
typedef Bounded<T extends num> = Box<T>;

String construction() {
  final flip = Flip.fields;
  final fixed = Fixed.fields;
  final repeated = Repeated.fields;
  final phantom = Phantom.new;
  final describe = Flip.describe;
  final x = flip<String, int>(1, 'two');
  final y = fixed<String>(3, 'four');
  final z = repeated<int>(5, 6);
  final n = phantom<String>(7);
  describe<String, int>(8, 'nine');
  return '${x.values}:${y.values}:${z.values}:${n.value}';
}

String identity() {
  final flip = Flip.fields;
  const raw = Flip.fields;
  const instantiated = raw<String, int>;
  const applied = Flip<String, int>.fields;
  const phantom = Phantom.new;
  final specific = phantom<int>;
  return '${identical(flip, raw)}:'
      '${identical(instantiated, flip<String, int>)}:'
      '${identical(applied, Pair<int, String>.fields)}:'
      '${identical(flip<String, int>, applied)}:'
      '${identical(Proper.fields, Pair.fields)}:'
      '${identical(phantom, Number.new)}:'
      '${identical(specific, phantom<String>)}:'
      '${identical(Phantom<int>.new, Number.new)}';
}

String constantCalls() {
  const flip = Flip.fields;
  const fixed = Fixed<String>.fields;
  const phantom = Phantom.new;
  const bounded = Bounded.new;
  final raw = Flip.fields;
  Pair<int, String> Function(int, String) inferred = raw;
  return '${flip<String, int>(1, 'two').values}:'
      '${fixed(3, 'four').values}:'
      '${phantom<String>(5).value}:'
      '${bounded<int>(6).value}:'
      '${inferred(7, 'eight').values}';
}

Object dynamicCall(int mode) {
  dynamic make = switch (mode) {
    0 => Flip.fields,
    1 => Phantom.new,
    _ => Bounded.new,
  };
  return switch (mode) {
    0 => make<String, int>('bad', 'right'),
    1 => make<int>(4),
    2 => make<String>('bad'),
    _ => make(3),
  };
}
