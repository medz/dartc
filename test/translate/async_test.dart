import 'support.dart';

void main() {
  agrees('async functions', r'''
Future<int> one() async => 1;
Future<int> add(Future<int> a, int b) async { final x = await a; print('add $x $b'); return x + b; }
Future<void> nothing() async { print('nothing'); }
void fire(String s) async { print('fire $s'); await null; print('fired $s'); }
Future<T> same<T>(T x) async { await 0; return x; }
Future<int> direct() async { print('direct'); return one(); }
Future<double> half(int n) async => n / 2;
class A { int n = 0; Future<int> inc([int by = 1]) async { n += by; await Future.value(); return n; } Future<int> get v async => n; Future<A> operator +(int k) async { await inc(k); return this; } static Future<String> name() async => 'A'; }
class B extends A { @override Future<int> inc([int by = 1]) async { print('B.inc'); return await super.inc(by * 2); } }
mixin M { Future<int> m(int k) async { await null; return k; } } class C with M {}
main() async {
  print('main'); fire('a'); print(await one()); print(await add(one(), 2)); await nothing(); print(await same('s')); print(await direct()); print(await half(3));
  final a = B(); print(await a.inc()); print(await a.inc(5)); print(await a.v); print((await (a + 1)).n); print(await A.name()); print(await C().m(6));
  final f = one(); print(f is Future<int>); print(await f + await f); print([await one(), 2, for (var i = 0; i < 3; i++) await same(i)]); print('${await one()} ${await same(true)}');
  var sum = 0; for (var i = 0; i < 5; i++) { sum += await add(Future.value(i), i); } print(sum); while (await same(sum > 0)) { sum -= 25; if (sum < 0) break; } print(sum);
  final g = () async { print('g'); await null; return 'g done'; }; print(await g()); Future<int> local(int n) async { if (n <= 1) return 1; return n * await local(n - 1); } print(await local(5));
  print(await (await same(one))()); dynamic d = one(); print(await d); Object o = one(); print(await o); int i = 3; print(await i); FutureOr<int> fo = 4; print(await fo); fo = one(); print(await fo); int? nul = sum > 9 ? 1 : null; print(await nul); print(await (sum > 0 ? one() : same(2)));
  print(await Future.wait([one(), same(2), half(4).then((x) => x.toInt())])); print(await one().then((x) => x * 10).whenComplete(() => print('complete'))); final fs = <Future<int>>[]; for (var k = 0; k < 3; k++) fs.add(Future.delayed(Duration(milliseconds: 90 - 40 * k), () { print('d$k'); return k; })); print(await Future.wait(fs)); print(await Future.any(fs));
  final xs = <int Function()>[]; for (var k = 0; k < 3; k++) { await null; xs.add(() => k++); } for (final x in xs) print(x() + x()); void v() async { print('v'); } (v as dynamic)() is Future ? print('future') : print('no'); await (v as dynamic)();
  switch (await one()) { case 1: print('is one'); default: print('other'); } print((await same((1, b: 2))).b); final (p, q) = await same((3, 4)); print(p + q); final s = switch (await same('x')) { 'x' => await same('y'), _ => 'z' }; print(s); assert(await one() == 2); if (await one() case final w when w == await one()) print('when $w'); A? none = sum > 99 ? A() : null; print(await none?.inc()); A na = none ?? await same(A()); print(na.n); na..n = await one()..n += 1; print(na.n); print(await one() == 1 && await same(true) || await same(false)); print(await same(null) ?? await same('default'));
}
''', imports: "import 'dart:async';");

  agrees(
    'order of microtasks and events',
    r'''
Future<void> steps(String name) async { for (var i = 0; i < 3; i++) { print('$name$i'); await null; } }
Future<String> slow(String s, int ms) async { await Future.delayed(Duration(milliseconds: ms)); print('slow $s'); return s; }
main() {
  print('start'); scheduleMicrotask(() => print('micro 1')); Future(() => print('event 1')); Timer.run(() => print('timer')); Timer(Duration(milliseconds: 60), () => print('timer 5')); Timer(Duration.zero, () { print('zero'); scheduleMicrotask(() => print('micro in zero')); Future.sync(() => print('sync')); });
  Future.microtask(() => print('micro 2')).then((_) => print('after micro 2')); Future.value(3).then((v) => print('value $v')); steps('a'); steps('b'); slow('x', 96).then(print); slow('y', 36).then(print);
  var n = 0, m = 0; Timer.periodic(Duration(milliseconds: 120), (t) { print('tick ${t.tick}'); if (++n == 3) { t.cancel(); print(t.isActive); } }); final c = Timer(Duration(milliseconds: 48), () => print('never')); c.cancel(); print(c.isActive);
  final done = Completer<int>(); done.future.then((v) => print('completed $v')); Future(() => done.complete(7)); print(done.isCompleted); final sync = Completer<int>.sync(); sync.future.then((v) => print('sync $v')); sync.complete(1); print('end'); Future.delayed(Duration(milliseconds: 12)).then((_) => Future(() => print('chained'))).then((_) => print('last')); Future(() async { await Future(() => print('inner')); print('outer'); });
  Future.doWhile(() async { await null; return ++m < 6; }).then((_) => print('did $m')); Future.forEach([1, 2, 3], (e) async { await null; print('each $e'); });
}
''',
    imports: "import 'dart:async';",
    isLong: true,
  );

  agrees('errors', r'''
Future<int> bad(String s) async { await null; throw s; }
Future<int> worse() async { throw StateError('now'); }
Future<int> tries(int n) async { try { if (n == 0) return await bad('zero'); if (n == 1) return await worse(); if (n == 2) throw n; return n; } on StateError catch (e) { print('state ${e.message}'); return -1; } on String catch (e, t) { print('string $e'); try { await bad('inner'); } catch (e2) { print('then $e2'); } return -2; } finally { print('finally $n'); await null; print('finally after'); } }
Future<void> loops() async { for (var i = 0; i < 3; i++) { try { if (i == 1) continue; if (i == 2) break; await bad('$i'); } catch (e) { print('loop $e'); try { rethrow; } catch (e) { print('again $e'); } } finally { await null; print('end $i'); } } }
Future<int> passes() => bad('passed'); Future<int> returns() async { try { return bad('returned'); } catch (e) { print('not here'); return 0; } }
main() async {
  for (var n = 0; n < 4; n++) { try { print(await tries(n)); } catch (e) { print('out $e'); } } await loops();
  try { await passes(); } catch (e) { print(e); } try { await returns(); } catch (e) { print(e); } await bad('c').catchError((e) { print('caught $e'); return 0; }); await bad('t').then((v) => print(v), onError: (e) => print('on $e')); print(await bad('x').then((v) => 'v').onError((e, s) => 'error $e'));
  try { await Future.wait([bad('w1'), bad('w2')]); } catch (e) { print('wait $e'); } try { await Future.delayed(Duration(milliseconds: 12), () => throw 'delayed'); } catch (e) { print(e); } try { await Future.error('direct'); } catch (e) { print(e); } try { await bad('time').timeout(Duration(seconds: 1)); } catch (e) { print(e); } try { await Completer().future.timeout(Duration(milliseconds: 24)); } catch (e) { print(e is TimeoutException); }
  final r = await runZonedGuarded(() async { Future(() => throw 'zoned'); await null; return 5; }, (e, s) => print('guard $e')); print(r); await Future.delayed(Duration(milliseconds: 12)); runZoned(() => print('in zone'), zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => parent.print(zone, '[$line]'))); print(Zone.current == Zone.root); await runZoned(() async { await null; print(Zone.current[#k]); }, zoneValues: {#k: 'value'});
  print('before'); Future(() => print('not reached after error')); unawaited(bad('uncaught')); await Future(() => print('gone'));
}
''', imports: "import 'dart:async';");

  agrees('streams', r'''
Stream<int> count(int n) async* { print('listen'); try { for (var i = 0; i < n; i++) { await null; yield i; } } finally { print('closed'); } }
Stream<T> both<T>(Stream<T> a, Stream<T> b) async* { yield* a; yield* b; }
Stream<int> fails() async* { yield 1; throw 'failed'; }
class S { final n = 3; Stream<int> get s async* { for (var i = 0; i < n; i++) yield i * n; } }
Future<int> find(Stream<int> s, int x) async { await for (final v in s) { if (v == 0) continue; print('see $v'); if (v == x) return v; if (v > 5) break; } return -1; }
main() async {
  await for (final v in count(3)) print(v); print(await count(4).toList()); print(await find(count(9), 2)); print(await find(count(20), 99)); print(await both(count(1), count(2)).join(',')); print(await S().s.map((x) => x + 1).where((x) => x.isOdd).toList());
  try { await for (final v in fails()) print(v); } catch (e) { print(e); } print(await fails().handleError((e) => print('h $e')).toList()); print(await Stream.fromIterable([1, 2, 3]).fold<int>(0, (a, b) => a + b)); print(await count(5).take(2).toList()); print(await count(3).first); print(await Stream.periodic(Duration(milliseconds: 12), (i) => i).take(3).toList()); try { await Stream<int>.empty().first; } catch (e) { print(e); }
  final c = StreamController<String>(); final sub = c.stream.listen((s) => print('got $s'), onDone: () => print('done'), onError: (e) => print('err $e')); c.add('a'); c.addError('b'); sub.pause(); c.add('c'); await null; sub.resume(); await c.close(); final b = StreamController<int>.broadcast(); b.stream.listen((x) => print('1: $x')); b.stream.listen((x) => print('2: $x')); b.add(5); await b.close();
  final st = count(100).listen(print); await Future.delayed(Duration(milliseconds: 12)); st.pause(); await st.cancel(); outer: await for (final a in count(3)) { await for (final (x, y) in Stream.fromIterable([(1, 2), (3, 4)])) { if (a == 1) continue outer; if (a == 2) break outer; print('$a $x $y'); } } final it = StreamIterator(count(2)); while (await it.moveNext()) print(it.current); print([await for (final v in count(2)) v * 2]); print(await count(3).transform(StreamTransformer<int, String>.fromHandlers(handleData: (d, sink) { sink.add('<$d>'); })).toList()); Stream<int> local() async* { yield* Stream.fromFuture(Future.value(8)); } print(await local().single); dynamic dy = count(2); await for (final v in dy) print('dyn $v'); print(await count(4).asyncMap((x) async => x * x).toList()); print(await count(2).expand((x) => [x, x]).length); final un = await count(3).reduce((a, b) => a + b); print(un);
}
''', imports: "import 'dart:async';");

  agrees('futures as types', r'''
Type typeOf<T>() => T;
bool fits<T>(Object? o) => o is T;
class G<T> { FutureOr<T> v; G(this.v); bool ok(Object? o) => o is FutureOr<T>; Future<T> get f async => v; FutureOr<List<T>> l() => []; R run<R>(FutureOr<R> Function(T) g, T t) => g(t) as R; }
FutureOr<int> maybe(bool b) => b ? 3 : Future.value(4);
FutureOr<void> vo() {}
Future<T> w<T>(FutureOr<T> Function() f) async => await f();
void take(FutureOr<int> x) => print(x is int ? 'int $x' : 'future');
extension FX<T> on FutureOr<T> { String get kind => this is Future<T> ? 'F' : 'V'; }
extension on Future<int> { Future<int> get twice async => await this * 2; }
class MyFuture<T> implements Future<T> { final Future<T> f; MyFuture(this.f); noSuchMethod(i) => super.noSuchMethod(i);
 Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) { print('then'); return f.then(onValue, onError: onError); } }
class P { const P(); Future<int> call() async => 5; }
Stream<int> gen(int n) async* { for (var i = 0; i < n; i++) yield i; }
void main() async {
  print(typeOf<FutureOr<int>>()); print(typeOf<FutureOr<Object>>()); print(typeOf<FutureOr<Never>>()); print(typeOf<FutureOr<Null>>()); print(typeOf<FutureOr<int>?>()); print(typeOf<FutureOr<int?>>()); print(typeOf<List<FutureOr<String>>>()); print(typeOf<FutureOr<dynamic>>()); print(typeOf<FutureOr<FutureOr<int>>>());
  print(fits<FutureOr<int>>(1)); print(fits<FutureOr<int>>('a')); print(fits<FutureOr<int>>(Future.value(1))); print(fits<FutureOr<int>>(Future.value('a'))); print(fits<FutureOr<num>>(Future<int>.value(1))); print(fits<FutureOr<Object>>(null)); print(fits<FutureOr<Null>>(null));
  print(await maybe(true) + await maybe(false)); await vo(); take(3); take(Future.value(1)); dynamic d = 'x'; try { take(d); } catch (e) { print(e); } d = Future.value('x'); try { take(d); } catch (e) { print('$e'.length > 5); }
  final g = G<int>(3); print(g.ok(1)); print(g.ok(Future.value(2))); print(g.ok('a')); print(await g.f); g.v = Future.value(9); print(await g.f); print((await g.l()).runtimeType); print(g.run<String>((n) => '$n', 4)); print(await w(() => 5)); print(await w(() async => 'q')); print(await w<num>(() => 2.5));
  print(maybe(true).kind); print(maybe(false).kind); print(await Future.value(21).twice); print(await MyFuture(Future.value(8))); print(await P()()); Future<int> Function() f = P().call; print(await f()); 
  FutureOr<int?> n = null; print(await n); final Object o = Future<String>.value('os'); print(await o); Future<Object> wide = Future<int>.value(6); print(await wide); print(wide.runtimeType); print((() async => 1)().runtimeType); print((() async {})().runtimeType); print(gen(2).runtimeType.toString().contains('int')); print(() async => 1); print(() sync* { yield 1; }); print(() async* { yield 1; });
  print(await gen(3).map((x) => x * x).toList()); final (a, b) = await (Future.value(1), Future.value('two')).wait; print('$a $b'); print(await [Future.value(1), Future.value(2)].wait); try { await (Future.value(1), Future<int>.error('boom')).wait; } catch (e) { print(e.runtimeType); } Future<int>? nf; print(await nf); nf?.ignore(); print(await Future.value(1).then<int>((v) async => v + 1));
  final sc = StreamController<int>(); sc.sink..add(1)..add(2); unawaited(sc.close()); print(await sc.stream.asBroadcastStream().last); Zone.current.run(() => print('zone')); print(await Stream.fromFutures([Future.value(1), Future.value(2)]).toSet());
  await Future.wait([for (var i = 0; i < 3; i++) Future(() async { await null; print('w$i'); })]); try { await Future.wait([Future.error('e1'), Future.value(2)], eagerError: true); } catch (e) { print(e); } scheduleMicrotask(() { throw 'final'; });
}
''', imports: "import 'dart:async';");

  agrees('in all kinds of members and expressions', r'''
Future<T> w<T>(T x) async { await null; return x; }
class Box<T> { T v; Box(this.v); Future<List<T>> list() async => [v, await w(v)]; Iterable<T> rep(int n) sync* { for (var i = 0; i < n; i++) yield v; } Stream<(int, T)> st(int n) async* { for (var i = 0; i < n; i++) { yield (i, await w(v)); } } Future<R> map<R>(FutureOr<R> Function(T) f) async { final r = await f(v); print('$T $R'); return r; } late final Future<T> lazy = (() async => await w(v))(); Type get t => T; Future<Type> tt() async { await null; return T; } }
mixin Mx<T> { T get mv; Future<String> sh() async { await null; return 'mx $mv ${T}'; } Iterable<T> it() sync* { yield mv; yield* [mv]; } }
class Cx extends Box<String> with Mx<int> { Cx(super.v); int get mv => v.length; @override Future<List<String>> list() async { final l = await super.list(); return [...l, 'cx']; } Future<int> cl() async { int f() => mv + 1; await null; int g() => f() + v.length; return g(); } }
extension Ex<T> on List<T> { Future<T> pick(int i) async { await null; return this[i]; } Iterable<(int, T)> num_() sync* { var i = 0; for (final e in this) yield (i++, e); } Stream<T> get str async* { yield* Stream.fromIterable(this); } }
extension type Et(int n) { Future<int> dbl() async => n * await w(2); Iterable<int> up() sync* { for (var i = 0; i < n; i++) yield i; } static Future<Et> mk(int n) async => Et(await w(n)); }
enum En { a, b; Future<En> next() async { await null; return values[(index + 1) % 2]; } }
Future<int> fin(int k) async { try { try { if (k == 0) return await w(10); if (k == 1) throw 'e'; } finally { await w(null); print('f1 $k'); if (k == 2) return 22; } } on String { return 33; } finally { print('f2 $k'); } return 44; }
Future<void> lab() async { outer: for (var i = 0; i < await w(3); i += await w(1)) { try { for (var j = 0; ; j++) { try { if (j == 1) continue outer; if (i == 2) break outer; print('$i $j'); } finally { await null; print('in'); } } } finally { print('out ${await w(i)}'); } } }
Future<String> sw(Object o) async => switch (o) { int n when await w(n > 2) => 'big $n', int n => 'small ${await w(n)}', [final a, final b] => '${await w(a)}-${await w(b)}', (x: final x) => await w('$x'), _ => throw ArgumentError('no $o') };
Future<int> fib(int n) async => n < 2 ? n : await fib(n - 1) + await fib(n - 2);
Iterable<String> perms(String s) sync* { if (s.length <= 1) { yield s; return; } for (var i = 0; i < s.length; i++) { for (final p in perms(s.replaceRange(i, i + 1, ''))) yield s[i] + p; } }
Stream<int> merge(Stream<int> a, Stream<int> b) { final c = StreamController<int>(); var open = 2; void done() { if (--open == 0) c.close(); } a.listen(c.add, onDone: done, onError: c.addError); b.listen(c.add, onDone: done); return c.stream; }
Future<void> args(int a, [int b = 2, int? c]) async { a += await w(1); b *= a; c ??= await w(b); void inc() { a++; b++; } inc(); await null; print('$a $b $c'); }
Future<void> named({required int x, String y = 'd'}) async { await null; print('$x $y'); }
int top = 0; Future<int> get tg async => ++top; set ts(int v) { () async { await null; top = v; }(); }
Object? thrown() async* {}
main() async {
  final b = Box(3); print(await b.list()); print(b.rep(2).toList()); print(await b.st(2).toList()); print(await b.map((n) => '$n!')); print(await b.map((n) async => n / 2)); print(await b.lazy); print(await b.lazy); print(await Box<num>(1).tt()); final c = Cx('abc'); print(await c.list()); print(await c.sh()); print(c.it().toList()); print(await c.cl()); print(await c.lazy);
  print(await [1, 2, 3].pick(1)); print(['a', 'b'].num_().toList()); print(await ['q'].str.toList()); print(await Et(4).dbl()); print(Et(3).up().toList()); print((await Et.mk(5)).n); print(await En.b.next()); for (var k = 0; k < 4; k++) print(await fin(k)); await lab(); for (final o in <Object>[1, 5, [1, 2], (x: 3)]) print(await sw(o)); try { await sw('z'); } catch (e) { print(e); } print(await fib(10)); print(perms('abcd').length); print(perms('abc').toList()); print((await merge(Stream.fromIterable([1, 2]), Stream.fromIterable([10, 20])).toList())..sort()); await args(1); await args(1, 5, 9); await named(x: await w(1)); await named(y: 'z', x: 2);
  print(await tg + await tg); ts = 50; await null; await null; print(top); final l = <int>[]..add(await w(1))..addAll([await w(2), ...await w([3, 4])]); print(l); final m = {await w('k'): await w(1), for (final e in await w([1, 2])) e: await w(e * e), if (await w(true)) 'if': 1}; print(m); String? ns = top > 0 ? null : 'x'; print(ns?.substring(await w(0)) ?? await w('nul')); print('a${await w('b')}c${[for (var i = 0; i < 2; i++) await w(i)]}'); var x = await w(5); x += await w(x) * 2; x -= x - await w(1); print(x); final fs = [for (var i = 0; i < 3; i++) () async { await null; return i * i; }]; print(await Future.wait(fs.map((f) => f()))); print(await (() async { try { return await Future<int>.error('E'); } on String catch (e) { return e.length; } })()); print(await w(1) < await w(2) && (await w(3)).isOdd); (await w(b))..v = 7..v += await w(1); print(b.v); print(await Future.wait([for (var i = 0; i < 3; i++) Future.microtask(() async { await null; return i; })])); await for (final (i, s) in Stream.fromIterable(['p', 'q']).map((s) => (s.length, s))) print('$i$s'); await Future.forEach(<int>[1, 2], (n) async => print(await w(n))); bool flag = false; await Future.any([w(1).then((_) => flag = true), Future.delayed(Duration(milliseconds: 3))]); print(flag); print((thrown() as Stream).runtimeType.toString().length > 3); late int lz; Future<void> setLz() async { lz = await w(9); } await setLz(); print(lz); print(await Stream.fromIterable([3, 1, 2]).asyncExpand((n) async* { for (var i = 0; i < n; i++) yield i; }).toList()); int? mb = await w<int?>(null); mb ??= await w(4); print(mb); double dd = await w(1.5); dd++; bool bb = await w(false); bb |= true; print('$dd $bb'); final rec = (await w(1), n: await w('r')); print(rec); if (await w((1, 2)) case (var p, var q) when await w(p < q)) print(p + q); do { x++; } while (await w(x < 4)); print(x); assert(await w(false)); print(await Function.apply(w, [6]));
}
''', imports: "import 'dart:async';");
}
