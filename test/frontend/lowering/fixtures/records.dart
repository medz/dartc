import 'effects.dart' as effects;

(int, {int a, int z}) build(int n) =>
    (z: effects.tick(n++), effects.tick(n++), a: effects.tick(n));

int fieldOrder(int n) {
  final r = build(n);
  return r.$1 * 100 + r.a * 10 + r.z;
}

int stopInMiddle(int n) =>
    (z: effects.tick(1), a: effects.tick(n), effects.tick(3)).$1;

bool emptyOrSingleton(bool empty) {
  final Record r = empty ? () : (1,);
  return r is ();
}

const coordinates = (x: 4, ('north',), y: 3);

String direction([((String,), {int x, int y}) point = coordinates]) =>
    point.$1.$1;

bool constantRecord() =>
    direction() == 'north' && coordinates == const (('north',), y: 3, x: 4);

bool recordShape(Object? x, bool wide) {
  final Record r = wide ? (x, mark: 'ok', extra: 0) : (mark: 'ok', x);
  return r is (int, {String mark});
}

bool equalFields(Object? x, Object? y) => (a: (x,), 7) == (7, a: (y,));

int castRecord(Object? x) {
  final Object value = (x, mark: effects.tick(7));
  final narrowed = value as (int, {int mark});
  return narrowed.$1 + effects.tick(narrowed.mark);
}

(int?, {int other})? optionalRecord(bool missing, int? n) =>
    missing ? null : (n, other: effects.tick(1));

int? shortChain(bool missing, int? n) => optionalRecord(missing, n)?.$1!;

int parenthesized(bool missing, int? n) => (optionalRecord(missing, n)?.$1)!;

int unusualNames(int n) {
  final r = (n, $2: 3, $01: 4);
  return r.$1 + r.$2 * 10 + r.$01 * 100;
}
