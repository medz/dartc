import 'other.dart' deferred as o hide X;
import 'other.dart' as eager show E;
import 'other.dart' deferred as p hide X;
import 'third.dart' deferred as t hide hidden;
import 'fourth.dart' as fourth;

import 'dart:math' deferred as m;

import 'other.dart' deferred as o2 hide X;

void go(String label, Object? Function() f) {
  try {
    print('$label ${f()}');
  } catch (e) {
    print('$label ${e.runtimeType} $e');
  }
}

Future<void> main() async {
  go('call', () => o.f()); // expect: call _DeferredNotLoadedError Deferred library o was not loaded.
  go('var', () => o.v); // expect: var _DeferredNotLoadedError Deferred library o was not loaded.
  go('set', () => o.v = 2); // expect: set _DeferredNotLoadedError Deferred library o was not loaded.
  go('const', () => o.c); // expect: const _DeferredNotLoadedError Deferred library o was not loaded.
  go('new', () => o.A(1)); // expect: new _DeferredNotLoadedError Deferred library o was not loaded.
  go('static', () => o.A.s); // expect: static _DeferredNotLoadedError Deferred library o was not loaded.
  go('tearoff', () => o.f is Function); // expect: tearoff _DeferredNotLoadedError Deferred library o was not loaded.
  go('type', () => eager.E is Object); // expect: type true
  go('arguments first', () {
    print('before');
    return o.g(print('argument'));
  });
  // expect: before
  // expect: arguments first _DeferredNotLoadedError Deferred library o was not loaded.
  go('math', () => m.max(1, 2)); // expect: math _DeferredNotLoadedError Deferred library m was not loaded.
  await more();
  // expect: static method _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: static step _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: static step _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: compound _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: if null _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: named _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: factory _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: reference _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: constructor _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: enum _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: type _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: static of alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: call of alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: set of alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: named of alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: reference of alias _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: call _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: cascade _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: interpolated _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: condition 1
  // expect: nested _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: spread _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: index _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: property _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: Deferred library p was not loaded.
  // expect: loop _DeferredNotLoadedError Deferred library p was not loaded.
  // expect: loop 1
  // expect: static method 4
  // expect: static step 7
  // expect: static step 7
  // expect: if null 5
  // expect: named 6
  // expect: factory 9
  // expect: reference Closure: (int) => int from Function 'id': static.
  // expect: constructor Closure: (Object?) => A from Function 'A.named': static.
  // expect: enum [E.a]
  // expect: type A
  // expect: alias 3
  // expect: static of alias 7
  // expect: call of alias 4
  // expect: call 8
  // expect: cascade [0, 1]
  // expect: index 0
  // expect: 3
  // expect: again 1
  go('lib tear', () => o.loadLibrary is Function); // expect: lib tear true
  final future = o.loadLibrary();
  print(future.runtimeType); // expect: Future<void>
  go('before await', () => o.f()); // expect: before await _DeferredNotLoadedError Deferred library o was not loaded.
  print(await future); // expect: null
  go('call', () => o.f()); // expect: call 1
  go('second prefix', () => o2.f()); // expect: second prefix _DeferredNotLoadedError Deferred library o2 was not loaded.
  go('var', () => o.v); // expect: var 1
  go('set', () => o.v = 2); // expect: set 2
  go('var', () => o.v); // expect: var 2
  go('const', () => o.c); // expect: const constant
  go('new', () => o.A(1).i); // expect: new 1
  go('static', () => o.A.s); // expect: static 7
  go('tearoff', () => o.f()); // expect: tearoff 1
  go('enum', () => o.E.a); // expect: enum E.a
  go('generic', () => o.id<int>(4)); // expect: generic 4
  go('object', () => o.A(5)); // expect: object Instance of 'A'
  print(await o.loadLibrary()); // expect: null
  final l = o.loadLibrary;
  print(l.runtimeType); // expect: () => Future<dynamic>
  print(await l()); // expect: null
  final loadThird = t.loadLibrary;
  go('third before calling the tear-off', () => t.x); // expect: third before calling the tear-off _DeferredNotLoadedError Deferred library t was not loaded.
  final third = loadThird();
  go('third before awaiting the tear-off', () => t.x); // expect: third before awaiting the tear-off _DeferredNotLoadedError Deferred library t was not loaded.
  print(await third); // expect: null
  go('third', () => t.x); // expect: third x
  go('third', () => t.y); // expect: third 1
  go('third', () => (t.y = 5)); // expect: third 5
  go('third', () => t.y); // expect: third 5
  go('init', () => t.lazy);
  // expect: initialized
  // expect: init 3
  go('compound', () => t.y += 2); // expect: compound 7
  go('getter', () => t.got); // expect: getter 8
  go('setter', () => t.got = 1);
  // expect: set 1
  // expect: setter 1
  await m.loadLibrary();
  go('math', () => m.max(1, 2)); // expect: math 2
  go('pi', () => m.pi); // expect: pi 3.141592653589793
  go('second prefix', () => o2.f()); // expect: second prefix _DeferredNotLoadedError Deferred library o2 was not loaded.
  print(await Future.wait([o2.loadLibrary(), o2.loadLibrary()])); // expect: [null, null]
  go('second prefix', () => o2.f()); // expect: second prefix 1
  go('other library', () => fourth.used()); // expect: other library _DeferredNotLoadedError Deferred library o was not loaded.
  await fourth.load();
  go('other library', () => fourth.used()); // expect: other library 1
  print(o.loadLibrary == o.loadLibrary); // expect: true
  print(identical(o.loadLibrary, o2.loadLibrary)); // expect: false
  print(o.loadLibrary is Future<void> Function()); // expect: true
}

Future<void> more() async {
  go('static method', () => p.A.make(4));
  go('static step', () => p.A.s++);
  go('static step', () => --p.A.s);
  go('compound', () => p.v += print('right') as int);
  go('if null', () => p.n ??= 5);
  go('named', () => p.A.named((print('argument') as dynamic)));
  go('factory', () => p.A.other());
  go('reference', () => p.id<int>);
  go('constructor', () => p.A.named);
  go('enum', () => p.E.values);
  go('type', () => p.A);
  go('alias', () => p.B(3));
  go('static of alias', () => p.B.s);
  go('call of alias', () => p.B.make(4));
  go('set of alias', () => p.B.s = 1);
  go('named of alias', () => p.B.named(5));
  go('reference of alias', () => p.B.make);
  go('call', () => p.function((print('argument') as dynamic)));
  go('cascade', () => p.list..add(1));
  go('interpolated', () => '${p.f()}');
  go('condition', () => true ? 1 : p.f());
  go('nested', () => [for (var i = 0; i < 2; i++) p.f()]);
  go('spread', () => [...p.list]);
  go('index', () => p.list[0]);
  go('property', () => p.list.length);
  try {
    print(await p.later());
  } catch (e) {
    print(e);
  }
  for (var i = 0; i < 2; i++) {
    go('loop', () => p.f());
    await p.loadLibrary();
  }
  go('static method', () => p.A.make(4).i);
  go('static step', () => p.A.s++);
  go('static step', () => --p.A.s);
  go('if null', () => p.n ??= 5);
  go('named', () => p.A.named(6).i);
  go('factory', () => p.A.other().i);
  go('reference', () => p.id<int>);
  go('constructor', () => p.A.named);
  go('enum', () => p.E.values);
  go('type', () => p.A);
  go('alias', () => p.B(3).i);
  go('static of alias', () => p.B.s);
  go('call of alias', () => p.B.make(4).i);
  go('call', () => p.function(8));
  go('cascade', () => p.list..add(1));
  go('index', () => p.list[0]);
  print(await p.later());
  final load = p.loadLibrary();
  go('again', () => p.f());
  await load;
}
