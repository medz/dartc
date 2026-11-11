import 'dart:ffi';

import 'package:dartc/interop.dart';

final class Key(final double value) {
  Key? next;
  @override
  bool operator ==(Object other) => throw StateError('Equality must not run');
  @override
  int get hashCode => throw StateError('hashCode must not run');
}

final class const Token(final int value);

Expando<Key> first = Expando('first'), second = Expando('second');
Key? root;
WeakReference<Key>? keyWatch, valueWatch;

void churn() {
  for (var i = 0; i < 20000; i++) {
    if (Key(i.toDouble()).value < 0) throw StateError('allocation');
  }
}

@Export<Double Function(Int64)>()
double properties(int count) {
  final create = Expando<double>.new;
  final a = create('same'), b = create('same');
  final keys = <Key>[];
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    final key = Key(i.toDouble());
    keys.add(key);
    a[key] = key.value;
    b[key] = -key.value;
  }
  for (final key in keys) {
    if (a[key] != key.value || b[key] != -key.value) return -1;
    a[key] = key.value + 0.5;
    sum += a[key]!;
    a[key] = null;
    if (a[key] != null || b[key] != -key.value) return -2;
  }
  final key = Key(42);
  a[key] = null;
  a[key] = 3.25;
  if (a[key] != 3.25 ||
      b[key] != null ||
      a.name != 'same' ||
      a.toString() != 'Expando:same' ||
      Expando().toString() != 'Expando:null') {
    return -3;
  }
  const constant = Token(7);
  a[constant] = 7;
  a[Token] = 8;
  final function = churn;
  a[function] = 9;
  a[keys] = 10;
  for (var round = 0; round < 3; round++) {
    for (var i = 0; i < count; i++) {
      a[Key(i.toDouble())] = i.toDouble();
    }
    churn();
    if (a[key] != 3.25) return -5;
  }
  return a[constant] == 7 && a[Token] == 8 && a[function] == 9 && a[keys] == 10
      ? sum
      : -4;
}

@Export<Void Function(Int8)>()
void createGraph(int mode) {
  first = Expando('first');
  second = Expando('second');
  final key = Key(1), middle = Key(2), value = Key(3);
  value.next = key;
  second[middle] = value;
  first[key] = middle;
  keyWatch = WeakReference(key);
  valueWatch = WeakReference(value);
  root = mode == 0 ? null : key;
  if (mode == 2) {
    first = Expando();
    second = Expando();
  }
}

@Export<Double Function(Int8)>()
double observeGraph(int which) {
  churn();
  return (which == 0 ? keyWatch : valueWatch)?.target?.value ?? -1;
}

@Export<Void Function()>()
void releaseGraph() => root = null;

@Export<Int8 Function(Int64)>()
int rejects(int kind) {
  final dynamic key = switch (kind) {
    0 => 42,
    1 => 1.25,
    2 => true,
    3 => 'key',
    4 => Pointer<Void>.fromAddress(0x1234),
    _ => null,
  };
  final expando = Expando<Object>();
  var rejected = 0;
  try {
    expando[key];
  } on ArgumentError catch (error) {
    if (identical(error.invalidValue, key)) rejected++;
  } on TypeError {
    if (key == null) rejected += 2;
  }
  try {
    expando[key] = null;
  } on ArgumentError catch (error) {
    if (identical(error.invalidValue, key)) rejected++;
  } on TypeError {
    if (key == null) rejected += 2;
  }
  return rejected;
}

@Export<Int8 Function()>()
int checkedValues() {
  final key = Key(0);
  final Expando<Object> values = Expando<int>();
  values[key] = 4;
  try {
    values[key] = 'wrong';
  } on TypeError {
    return values[key] == 4 ? 1 : 0;
  }
  return -1;
}

@Export<Int8 Function(Int64, Double)>()
int identityHashes(int integer, double floating) {
  Object integerValue() => integer + 0;
  Object floatingValue() => floating + 0;
  final key = Key(1);
  final hash = identityHashCode(key);
  churn();
  return hash == identityHashCode(key) &&
          identityHashCode(integerValue()) ==
              identityHashCode(integerValue()) &&
          identityHashCode(floatingValue()) ==
              identityHashCode(floatingValue()) &&
          identityHashCode(true) == identityHashCode(true) &&
          identityHashCode(null) == identityHashCode(null)
      ? 1
      : 0;
}
