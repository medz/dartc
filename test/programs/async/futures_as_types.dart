import 'dart:async';

Type typeOf<T>() => T;
bool fits<T>(Object? o) => o is T;

class G<T> {
  FutureOr<T> v;
  G(this.v);
  bool ok(Object? o) => o is FutureOr<T>;
  Future<T> get f async => v;
  FutureOr<List<T>> l() => [];
  R run<R>(FutureOr<R> Function(T) g, T t) => g(t) as R;
}

FutureOr<int> maybe(bool b) => b ? 3 : Future.value(4);
FutureOr<void> vo() {}
Future<T> w<T>(FutureOr<T> Function() f) async => await f();
void take(FutureOr<int> x) => print(x is int ? 'int $x' : 'future');

extension FX<T> on FutureOr<T> {
  String get kind => this is Future<T> ? 'F' : 'V';
}

extension on Future<int> {
  Future<int> get twice async => await this * 2;
}

class MyFuture<T> implements Future<T> {
  final Future<T> f;
  MyFuture(this.f);
  noSuchMethod(i) => super.noSuchMethod(i);
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) {
    print('then');
    return f.then(onValue, onError: onError);
  }
}

class P {
  const P();
  Future<int> call() async => 5;
}

Stream<int> gen(int n) async* {
  for (var i = 0; i < n; i++) yield i;
}

void main() async {
  print(typeOf<FutureOr<int>>()); // expect: FutureOr<int>
  print(typeOf<FutureOr<Object>>()); // expect: Object
  print(typeOf<FutureOr<Never>>()); // expect: Future<Never>
  print(typeOf<FutureOr<Null>>()); // expect: Future<Null>?
  print(typeOf<FutureOr<int>?>()); // expect: FutureOr<int>?
  print(typeOf<FutureOr<int?>>()); // expect: FutureOr<int?>
  print(typeOf<List<FutureOr<String>>>()); // expect: List<FutureOr<String>>
  print(typeOf<FutureOr<dynamic>>()); // expect: dynamic
  print(typeOf<FutureOr<FutureOr<int>>>()); // expect: FutureOr<FutureOr<int>>
  print(fits<FutureOr<int>>(1)); // expect: true
  print(fits<FutureOr<int>>('a')); // expect: false
  print(fits<FutureOr<int>>(Future.value(1))); // expect: true
  print(fits<FutureOr<int>>(Future.value('a'))); // expect: false
  print(fits<FutureOr<num>>(Future<int>.value(1))); // expect: true
  print(fits<FutureOr<Object>>(null)); // expect: false
  print(fits<FutureOr<Null>>(null)); // expect: true
  print(await maybe(true) + await maybe(false)); // expect: 7
  await vo();
  take(3); // expect: int 3
  take(Future.value(1)); // expect: future
  dynamic d = 'x';
  try {
    take(d);
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'FutureOr<int>'
  d = Future.value('x');
  try {
    take(d);
  } catch (e) {
    print('$e'.length > 5);
  }
  // expect: true
  final g = G<int>(3);
  print(g.ok(1)); // expect: true
  print(g.ok(Future.value(2))); // expect: true
  print(g.ok('a')); // expect: false
  print(await g.f); // expect: 3
  g.v = Future.value(9);
  print(await g.f); // expect: 9
  print((await g.l()).runtimeType); // expect: List<int>
  print(g.run<String>((n) => '$n', 4)); // expect: 4
  print(await w(() => 5)); // expect: 5
  print(await w(() async => 'q')); // expect: q
  print(await w<num>(() => 2.5)); // expect: 2.5
  print(maybe(true).kind); // expect: V
  print(maybe(false).kind); // expect: F
  print(await Future.value(21).twice); // expect: 42
  print(await MyFuture(Future.value(8)));
  // expect: then
  // expect: 8
  print(await P()()); // expect: 5
  Future<int> Function() f = P().call;
  print(await f()); // expect: 5
  FutureOr<int?> n = null;
  print(await n); // expect: null
  final Object o = Future<String>.value('os');
  print(await o); // expect: os
  Future<Object> wide = Future<int>.value(6);
  print(await wide); // expect: 6
  print(wide.runtimeType); // expect: Future<int>
  print((() async => 1)().runtimeType); // expect: Future<int>
  print((() async {})().runtimeType); // expect: Future<Null>
  print(gen(2).runtimeType.toString().contains('int')); // expect: true
  print(() async => 1); // expect: Closure: () => Future<int>
  print(() sync* {
    yield 1;
  }); // expect: Closure: () => Iterable<int>
  print(() async* {
    yield 1;
  }); // expect: Closure: () => Stream<int>
  print(await gen(3).map((x) => x * x).toList()); // expect: [0, 1, 4]
  final (a, b) = await (Future.value(1), Future.value('two')).wait;
  print('$a $b'); // expect: 1 two
  print(await [Future.value(1), Future.value(2)].wait); // expect: [1, 2]
  try {
    await (Future.value(1), Future<int>.error('boom')).wait;
  } catch (e) {
    print(e.runtimeType);
  }
  // expect: ParallelWaitError<(int?, int?), (AsyncError?, AsyncError?)>
  Future<int>? nf;
  print(await nf); // expect: null
  nf?.ignore();
  print(await Future.value(1).then<int>((v) async => v + 1)); // expect: 2
  final sc = StreamController<int>();
  sc.sink
    ..add(1)
    ..add(2);
  unawaited(sc.close());
  print(await sc.stream.asBroadcastStream().last); // expect: 2
  Zone.current.run(() => print('zone')); // expect: zone
  print(await Stream.fromFutures([Future.value(1), Future.value(2)]).toSet());
  // expect: {1, 2}
  await Future.wait([
    for (var i = 0; i < 3; i++)
      Future(() async {
        await null;
        print('w$i');
      }),
  ]);
  // expect: w0
  // expect: w1
  // expect: w2
  try {
    await Future.wait([Future.error('e1'), Future.value(2)], eagerError: true);
  } catch (e) {
    print(e);
  }
  // expect: e1
  scheduleMicrotask(() {
    throw 'final';
  });
}
// stderr: Unhandled exception:
// stderr: final
// exit: 255
