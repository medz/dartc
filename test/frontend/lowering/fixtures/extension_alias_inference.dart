extension type Pair<A, B>((A, B) values);
typedef Flip<X, Y> = Pair<Y, X>;

String inferred() {
  Pair<int, String> Function((int, String)) make = Flip.new;
  final pair = make((7, 'eight')).values;
  return '${pair.$1}:${pair.$2}';
}
