import 'dart:async';

Future<int> bad(String s) async {
  await null;
  throw s;
}

Future<int> worse() async {
  throw StateError('now');
}

Future<int> tries(int n) async {
  try {
    if (n == 0) return await bad('zero');
    if (n == 1) return await worse();
    if (n == 2) throw n;
    return n;
  } on StateError catch (e) {
    print('state ${e.message}');
    return -1;
  } on String catch (e, t) {
    print('string $e');
    try {
      await bad('inner');
    } catch (e2) {
      print('then $e2');
    }
    return -2;
  } finally {
    print('finally $n');
    await null;
    print('finally after');
  }
}

Future<void> loops() async {
  for (var i = 0; i < 3; i++) {
    try {
      if (i == 1) continue;
      if (i == 2) break;
      await bad('$i');
    } catch (e) {
      print('loop $e');
      try {
        rethrow;
      } catch (e) {
        print('again $e');
      }
    } finally {
      await null;
      print('end $i');
    }
  }
}

Future<int> passes() => bad('passed');
Future<int> returns() async {
  try {
    return bad('returned');
  } catch (e) {
    print('not here');
    return 0;
  }
}

main() async {
  for (var n = 0; n < 4; n++) {
    try {
      print(await tries(n));
    } catch (e) {
      print('out $e');
    }
  }
  // expect: string zero
  // expect: then inner
  // expect: finally 0
  // expect: finally after
  // expect: -2
  // expect: state now
  // expect: finally 1
  // expect: finally after
  // expect: -1
  // expect: finally 2
  // expect: finally after
  // expect: out 2
  // expect: finally 3
  // expect: finally after
  // expect: 3
  // expect: loop 0
  // expect: again 0
  // expect: end 0
  // expect: end 1
  // expect: end 2
  // expect: passed
  // expect: returned
  // expect: caught c
  // expect: on t
  // expect: error x
  // expect: wait w1
  // expect: delayed
  // expect: direct
  // expect: time
  // expect: true
  // expect: 5
  // expect: guard zoned
  // expect: [in zone]
  // expect: true
  // expect: value
  // expect: before
  await loops();
  try {
    await passes();
  } catch (e) {
    print(e);
  }
  try {
    await returns();
  } catch (e) {
    print(e);
  }
  await bad('c').catchError((e) {
    print('caught $e');
    return 0;
  });
  await bad('t').then((v) => print(v), onError: (e) => print('on $e'));
  print(await bad('x').then((v) => 'v').onError((e, s) => 'error $e'));
  try {
    await Future.wait([bad('w1'), bad('w2')]);
  } catch (e) {
    print('wait $e');
  }
  try {
    await Future.delayed(Duration(milliseconds: 12), () => throw 'delayed');
  } catch (e) {
    print(e);
  }
  try {
    await Future.error('direct');
  } catch (e) {
    print(e);
  }
  try {
    await bad('time').timeout(Duration(seconds: 1));
  } catch (e) {
    print(e);
  }
  try {
    await Completer().future.timeout(Duration(milliseconds: 24));
  } catch (e) {
    print(e is TimeoutException);
  }
  final r = await runZonedGuarded(() async {
    Future(() => throw 'zoned');
    await null;
    return 5;
  }, (e, s) => print('guard $e'));
  print(r);
  await Future.delayed(Duration(milliseconds: 12));
  runZoned(
    () => print('in zone'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => parent.print(zone, '[$line]'),
    ),
  );
  print(Zone.current == Zone.root);
  await runZoned(() async {
    await null;
    print(Zone.current[#k]);
  }, zoneValues: {#k: 'value'});
  print('before');
  Future(() => print('not reached after error'));
  unawaited(bad('uncaught'));
  await Future(() => print('gone'));
}
// stderr: Unhandled exception:
// stderr: uncaught
// exit: 255
