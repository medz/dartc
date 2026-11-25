// long
import 'dart:async';

Future<void> steps(String name) async {
  for (var i = 0; i < 3; i++) {
    print('$name$i');
    await null;
  }
}

Future<String> slow(String s, int ms) async {
  await Future.delayed(Duration(milliseconds: ms));
  print('slow $s');
  return s;
}

main() {
  print('start'); // expect: start
  scheduleMicrotask(() => print('micro 1'));
  Future(() => print('event 1'));
  Timer.run(() => print('timer'));
  Timer(Duration(milliseconds: 60), () => print('timer 5'));
  Timer(Duration.zero, () {
    print('zero');
    scheduleMicrotask(() => print('micro in zero'));
    Future.sync(() => print('sync'));
  });
  Future.microtask(() => print('micro 2')).then((_) => print('after micro 2'));
  Future.value(3).then((v) => print('value $v'));
  steps('a'); // expect: a0
  steps('b'); // expect: b0
  slow('x', 96).then(print);
  slow('y', 36).then(print);
  var n = 0, m = 0;
  Timer.periodic(Duration(milliseconds: 120), (t) {
    print('tick ${t.tick}');
    if (++n == 3) {
      t.cancel();
      print(t.isActive);
    }
  });
  final c = Timer(Duration(milliseconds: 48), () => print('never'));
  c.cancel();
  print(c.isActive); // expect: false
  final done = Completer<int>();
  done.future.then((v) => print('completed $v'));
  Future(() => done.complete(7));
  print(done.isCompleted); // expect: false
  final sync = Completer<int>.sync();
  sync.future.then((v) => print('sync $v'));
  sync.complete(1); // expect: sync 1
  print('end');
  // expect: end
  // expect: micro 1
  // expect: micro 2
  // expect: after micro 2
  // expect: value 3
  // expect: a1
  // expect: b1
  // expect: each 1
  // expect: a2
  // expect: b2
  // expect: each 2
  // expect: each 3
  // expect: did 6
  // expect: event 1
  // expect: timer
  // expect: zero
  // expect: sync
  // expect: micro in zero
  // expect: completed 7
  // expect: inner
  // expect: outer
  // expect: chained
  // expect: last
  // expect: slow y
  // expect: y
  // expect: timer 5
  // expect: slow x
  // expect: x
  // expect: tick 1
  // expect: tick 2
  // expect: tick 3
  // expect: false
  Future.delayed(Duration(milliseconds: 12))
      .then((_) => Future(() => print('chained')))
      .then((_) => print('last'));
  Future(() async {
    await Future(() => print('inner'));
    print('outer');
  });
  Future.doWhile(() async {
    await null;
    return ++m < 6;
  }).then((_) => print('did $m'));
  Future.forEach([1, 2, 3], (e) async {
    await null;
    print('each $e');
  });
}
