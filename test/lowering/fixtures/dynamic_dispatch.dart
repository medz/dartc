import 'effects.dart' as effects;

class Box(var int value) {
  int method(int x, {int z = 0, int a = 0}) => value + x + z + a;
  T generic<T extends num>(T x) => x;
  Type defaultType<T extends num>() => T;
  dynamic get getter {
    effects.tick(30);
    return method;
  }

  Function get unshaped => method;
  Box self(int mark) {
    effects.tick(mark);
    return this;
  }

  int operator [](int key) => value + effects.tick(key);
  void operator []=(int key, int x) {
    effects.tick(40);
    value = x + key;
  }

  int operator +(int x) => value + x;
  int operator -() => -value;
  int operator -(int x) => value - x;
  @override
  bool operator ==(Object other) => other is Box && value == other.value;
  @override
  int get hashCode => value;
  int operator ~() => ~value;
  int call(int x) => value + x;
  // Accessed dynamically.
  // ignore: unused_element
  int _private(int x) => value + x;
}

class Missing() {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return invocation.isSetter ? 100 : 7;
  }
}

int named() {
  dynamic d = Box(10);
  return d.method(effects.tick(1), z: effects.tick(2), a: effects.tick(3));
}

int getterOrder(int form) {
  final box = Box(10);
  dynamic d = box;
  if (form == 0) return d.getter(effects.tick(1));
  if (form == 1) return (d.getter)(effects.tick(1));
  if (form == 2) return box.getter(effects.tick(1));
  if (form == 3) return (box.getter)(effects.tick(1));
  return box.unshaped(effects.tick(1));
}

int calls(int form) {
  dynamic d = Box(10);
  Function fn = Box(20).method;
  if (form == 0) return d(1);
  if (form == 1) return d.call(1);
  if (form == 2) return fn(1);
  if (form == 3) return fn.call(1);
  if (form == 4) return (fn.call)(1);
  if (form == 5) return (d.call)(1);
  return d._private(1);
}

int updates(bool missing) {
  dynamic d = missing ? null : Box(1);
  d
    ?..self(effects.tick(2))
    ..value += effects.tick(3)
    ..[effects.tick(4)] += effects.tick(5);
  if (missing) return 0;
  final old = d.value++;
  final current = ++d.value;
  final assigned = d.value = effects.tick(6);
  final indexed = d[effects.tick(7)] = effects.tick(8);
  return old + current + assigned + indexed + d.value;
}

Object? nullChain(bool missing) {
  dynamic d = missing ? null : Box(1);
  return d?.self(effects.tick(2)).method(effects.tick(3));
}

int operators(dynamic d) => (d + 2) + (d * 3) + (-d) + (~d);
int userOperators() {
  dynamic d = Box(4);
  return (d + 2) + (-d) + (~d) + (d - 2);
}

bool equality(dynamic d) => d == null || d != 2;
int genericCalls(int form) {
  dynamic d = Box(1);
  if (form == 0) return d.generic<int>(3);
  if (form == 1) return d.generic(4);
  return d.defaultType() == num ? 1 : 0;
}

int failures(int form) {
  dynamic d = Box(1);
  dynamic bad = 'bad';
  try {
    if (form == 0) return d.method(bad, z: effects.tick(2));
    if (form == 1) return d.method(effects.tick(1), nope: effects.tick(2));
    if (form == 2) return d.generic<String>(bad);
    if (form == 3) return d.absent(effects.tick(1));
    return d.method(effects.tick(-1));
  } on NoSuchMethodError {
    return 10;
  } on TypeError {
    return 20;
  } on StateError {
    return 30;
  }
}

int fallback(int form) {
  dynamic d = Missing();
  if (form == 0) return d.absent(effects.tick(1), z: effects.tick(2));
  if (form == 1) return d.absent;
  if (form == 2) return d.absent = effects.tick(3);
  return d[effects.tick(4)] = effects.tick(5);
}

bool objectMembers() {
  dynamic d;
  final int hash = d.hashCode;
  return d.toString() == 'null' &&
      d.runtimeType == Null &&
      hash == null.hashCode;
}

int bounded<T extends Function>(T fn, int form) {
  if (form == 0) return fn(effects.tick(1));
  if (form == 1) return fn.call(effects.tick(1));
  return (fn.call)(effects.tick(1));
}

int boundedCalls(int form) {
  int plain(int x) => x + 10;
  T generic<T extends num>(T x) => x;
  return form < 3 ? bounded(plain, form) : bounded(generic, form - 3);
}

int getterFailures(int form) {
  final box = Box(1);
  dynamic bad = 'bad';
  try {
    if (form == 0) return box.getter(bad, z: effects.tick(2));
    if (form == 1) return (box.getter)(bad, z: effects.tick(2));
    if (form == 2) return box.unshaped(bad, z: effects.tick(2));
    return (box.unshaped)(bad, z: effects.tick(2));
  } on TypeError {
    return 20;
  }
}

Object binary(dynamic d, int form) {
  return switch (form) {
    0 => d - 2,
    1 => d / 2,
    2 => d ~/ 2,
    3 => d % 3,
    4 => d & 3,
    5 => d | 3,
    6 => d ^ 3,
    7 => d << 1,
    8 => d >> 1,
    9 => d >>> 1,
    10 => d < 3,
    11 => d <= 3,
    12 => d > 3,
    _ => d >= 3,
  };
}

class NullableBox(var int? value);
int nullAssignments(bool missing) {
  dynamic d = NullableBox(missing ? null : 1);
  final first = d.value ??= effects.tick(2);
  final second = d.value ??= effects.tick(3);
  return first + second;
}

Object? nullIndex(bool missing) {
  dynamic d = missing ? null : Box(1);
  return d?[effects.tick(2)] += effects.tick(3);
}

int functionCascade(bool missing) {
  Function? fn = missing ? null : Box(1).method;
  // Exercise the cascade call selector.
  // ignore: avoid_single_cascade_in_expression_statements
  fn?..call(effects.tick(2));
  return missing ? 0 : 1;
}

bool objectTearoffs() {
  dynamic d;
  final fn = d.toString;
  return fn() == 'null' && fn == d.toString;
}

class DefaultOwner<T>() {
  Type method<U extends T>() => U;
  dynamic closure() =>
      <U extends T>() => U;
}

class DefaultBox<T>();
typedef DefaultAlias<U extends int> = DefaultBox<U>;
typedef DefaultAliasList<U extends num> = DefaultBox<List<U>>;
dynamic defaultOuter<V>() =>
    <U extends V>() => U;
int genericEnvironments() {
  dynamic a = DefaultOwner<int>();
  dynamic m = a.method;
  dynamic c = a.closure();
  dynamic d = defaultOuter<int>();
  dynamic e = DefaultAlias.new;
  dynamic f = DefaultAliasList.new;
  return (m() == int ? 1 : 0) +
      (c() == int ? 2 : 0) +
      (d() == int ? 4 : 0) +
      (e() is DefaultBox<int> ? 8 : 0) +
      (f() is DefaultBox<List<num>> ? 16 : 0);
}

class RecursiveBound<T extends RecursiveBound<T>>();

class ShapeReceiver() {
  int f<T extends RecursiveBound<T>>(T x) => 1;
  int g<T extends num>(T x, {required int y}) => 1;
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.typeArguments.length * 10 + i.positionalArguments.length;
}

int shapeBeforeBounds() {
  dynamic d = ShapeReceiver();
  final a = d.f();
  final b = d.g<String>('bad');
  dynamic f = ShapeReceiver().g<int>;
  try {
    f<String>('bad', y: 0);
    return 0;
  } on NoSuchMethodError {
    return a + b + 100;
  }
}

bool customEquality() {
  dynamic a = Box(1);
  dynamic b = Box(1);
  return a == b && a != Box(2) && a != null && null != a;
}

class InvocationCapture() {
  Invocation? last;
  @override
  dynamic noSuchMethod(Invocation i) {
    last = i;
    return i;
  }
}

String describeInvocation(Invocation i) {
  var result =
      '${i.memberName}:${i.isMethod}/${i.isGetter}/${i.isSetter}/${i.isAccessor}:${i.typeArguments}:${i.positionalArguments}:';
  for (final entry in i.namedArguments.entries) {
    result += '${entry.key}=${entry.value},';
  }
  return result;
}

String invocationData() {
  final c = InvocationCapture();
  dynamic d = c;
  final a = describeInvocation(
    d.foo<int>(effects.tick(1), z: effects.tick(2), a: effects.tick(3)),
  );
  final b = describeInvocation(d.foo);
  d.foo = 4;
  final s = describeInvocation(c.last!);
  final u = describeInvocation(-d);
  final ix = describeInvocation(d[5]);
  d[6] = 7;
  return '$a|$b|$s|$u|$ix|${describeInvocation(c.last!)}';
}
