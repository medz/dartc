// Programs whose objects are gone when the memory is collected. The second one
// opens `LIBRARY`, which is made of what comes first.

const weakDart = r'''
class P {
  final int n;
  P(this.n);
}

int garbage() {
  var total = 0;
  for (var i = 0; i < 400; i++) {
    total += List.filled(200000, i).length;
  }
  return total;
}

WeakReference<P>? weak, kept;
final expando = Expando<P>('name');
final keys = <P>[];
List<WeakReference<P>> values = [];

@pragma('vm:never-inline')
void make(P strong) {
  weak = WeakReference(P(1));
  kept = WeakReference(strong);
  for (var i = 0; i < 5; i++) {
    final key = P(i), value = P(i * 10);
    expando[key] = value;
    values.add(WeakReference(value));
    if (i.isEven) keys.add(key);
  }
  // A chain, and a cycle through the expando.
  var at = P(100);
  keys.add(at);
  for (var i = 0; i < 4; i++) {
    final next = P(101 + i);
    expando[at] = next;
    values.add(WeakReference(next));
    at = next;
  }
  final a = P(7), b = P(8);
  expando[a] = b;
  expando[b] = a;
  values.add(WeakReference(a));
}

// Their order is not told.
final found = <String>[];
final finalizer = Finalizer<int>((n) => found.add('finalized $n'));
final other = Finalizer<String>((s) => found.add('other $s'));

@pragma('vm:never-inline')
void attach(P strong, P detach) {
  finalizer.attach(strong, 1);
  finalizer.attach(P(2), 2);
  other.attach(P(3), 'three', detach: detach);
  finalizer.attach(P(4), 4, detach: detach);
}

void main() async {
  final strong = P(2), detach = P(3);
  make(strong);
  garbage();
  print(weak!.target == null);
  print(identical(kept!.target, strong));
  print([for (final key in keys) expando[key]?.n]);
  print([for (final value in values) value.target?.n]);
  attach(strong, detach);
  finalizer.detach(detach);
  garbage();
  print(found);
  await Future(() {});
  await Future(() {});
  print(found..sort());
  print((strong.n, detach.n));
  try {
    WeakReference(1);
  } catch (e) {
    print(e);
  }
  try {
    finalizer.attach('text', 1);
  } catch (e) {
    print(e);
  }
}
''';

const finalizersC = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static int calls;
static int64_t total;
void finalize(void *token) { calls++; total += (intptr_t)token; if (token == (void *)1) { printf("at the end\n"); fflush(stdout); } }
int32_t count(void) { return calls; }
int64_t sum(void) { return total; }
uint8_t *makeMemory(int32_t n) { return calloc(n, 1); }
void freeMemory(void *p) { total += 1000; free(p); }
''';

const finalizableExitsDart = r'''
import 'dart:ffi';

final lib = DynamicLibrary.open('LIBRARY');
final sum = lib.lookupFunction<Int64 Function(), int Function()>('sum');
final finalizer = NativeFinalizer(lib.lookup('finalize'));

class P implements Finalizable {}

P attach(int token) {
  final value = P();
  finalizer.attach(value, Pointer.fromAddress(token));
  return value;
}

List<int>? garbage;

void probe(int tokens) {
  garbage = List.filled(16, tokens);
  print(sum() & tokens);
}

void stopAtSecond(int round) {
  if (round == 2) throw 'stop';
}

void infiniteLoop() {
  final local = attach(512);
  var round = 0;
  for (;;) {
    probe(512);
    stopAtSecond(++round);
  }
}

int returns() {
  final outer = attach(2);
  try {
    final middle = attach(4);
    try {
      final inner = attach(8);
      probe(14);
      return 17;
    } finally {
      probe(6);
    }
  } finally {
    probe(2);
  }
}

void loops() {
  for (var i = 0; i < 2; i++) {
    final token = 16 << i;
    try {
      final local = attach(token);
      probe(token);
      if (i == 0) continue;
      break;
    } finally {
      print(i);
    }
  }
}

Future<int> asyncReturn() async {
  final outer = attach(64);
  try {
    return 23;
  } finally {
    await Future<void>.value();
    probe(64);
  }
}

void catches() {
  try {
    throw attach(128);
  } on P catch (p) {
    probe(128);
  }
  try {
    try {
      throw 'again';
    } catch (_) {
      final local = attach(256);
      probe(256);
      rethrow;
    }
  } catch (error) {
    print(error);
  }
}

void main() async {
  try {
    infiniteLoop();
  } on String {}
  print(returns());
  loops();
  print(await asyncReturn());
  catches();
}
''';

const finalizersDart = r'''
import 'dart:ffi';
import 'dart:typed_data';

final lib = DynamicLibrary.open('LIBRARY');
final finalizePtr = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>('finalize');
final count = lib.lookupFunction<Int32 Function(), int Function()>('count');
final sum = lib.lookupFunction<Int64 Function(), int Function()>('sum');
final makeMemory = lib.lookupFunction<Pointer<Uint8> Function(Int32), Pointer<Uint8> Function(int)>('makeMemory');
final freeMemoryPtr = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>('freeMemory');

final finalizer = NativeFinalizer(finalizePtr);

class P implements Finalizable {
  final int n;
  P(this.n);
}

Pointer<Void> token(int n) => Pointer.fromAddress(n);

int garbage() {
  var total = 0;
  for (var i = 0; i < 400; i++) {
    total += List.filled(200000, i).length;
  }
  return total;
}

@pragma('vm:never-inline')
void attach(P strong, P detach) {
  finalizer.attach(strong, token(1));
  finalizer.attach(P(2), token(2));
  finalizer.attach(P(3), token(4), detach: detach);
  finalizer.attach(P(4), token(8), externalSize: 1000);
  finalizer.attach(P(5), token(16), externalSize: 1000, detach: P(9));
}

@pragma('vm:never-inline')
void lists() {
  final l = makeMemory(10).asTypedList(10, finalizer: freeMemoryPtr.cast());
  l[3] = 7;
  print(l);
}

/// Memory that only finalizers free.
int external() {
  var most = 0;
  for (var i = 0; i < 2000; i++) {
    final p = P(i);
    finalizer.attach(p, token(0), externalSize: 1 << 20);
    final open = i + 1 - (count() - base);
    if (open > most) most = open;
  }
  return most;
}

class Q implements Finalizable {
  int n = 1;
  @pragma('vm:never-inline')
  int method() {
    final before = count();
    garbage();
    return count() - before;
  }
}

class Plain {}

@pragma('vm:never-inline')
void scopes(Object? o, bool yes) {
  int lost(void Function() f) {
    garbage();
    final before = count();
    f();
    return count() - before;
  }

  P made(int n) {
    final p = P(n);
    finalizer.attach(p, token(0));
    return p;
  }

  print(lost(() {
    final p = made(1);
    garbage();
  }));
  print(lost(() {
    void f(P p) {
      garbage();
    }

    f(made(1));
  }));
  print(lost(() {
    for (final p in [made(1)]) {
      garbage();
    }
  }));
  print(lost(() {
    if (made(1) case final p) {
      garbage();
      if (yes) return;
    }
  }));
  print(lost(() {
    switch (made(1)) {
      case final p:
        garbage();
    }
  }));
  print(lost(() {
    final (p, x) = (made(1), 2);
    garbage();
    print(x);
  }));
  print(lost(() {
    while (true) {
      final p = made(1);
      garbage();
      if (yes) break;
    }
  }));
  print(lost(() {
    try {
      final p = made(1);
      garbage();
      throw 'thrown';
    } catch (e) {
      print(e);
    }
  }));
  final q = Q();
  finalizer.attach(q, token(0));
  print(lost(() => print(q.method())));
  print(q.n);
  print(lost(() {
    Q make() {
      final q = Q();
      finalizer.attach(q, token(0));
      return q;
    }

    print(make().method());
  }));
}

int base = 0;

void main() async {
  final strong = P(2), detach = P(3);
  attach(strong, detach);
  finalizer.detach(detach);
  print((count(), sum()));
  garbage();
  print((count(), sum()));
  await Future(() {});
  print((count(), sum()));
  lists();
  garbage();
  print((count(), sum()));
  scopes(1, true);
  garbage();
  base = count();
  print(external() < 1000);
  print((strong.n, detach.n));
  for (final use in [
    () => finalizer.attach(strong, token(1), externalSize: -1),
    () => finalizer.attach(strong, token(32), detach: 5),
  ]) {
    try {
      use();
      print('ok');
    } catch (e) {
      print(e);
    }
  }
}
''';
