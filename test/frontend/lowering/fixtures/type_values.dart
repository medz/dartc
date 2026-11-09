// ignore_for_file: use_primary_constructors, unnecessary_type_name_in_constructor, unnecessary_type_check
typedef Ints = List<int>;
typedef RawBound<T extends num> = List<T>;
typedef FnA = T Function<T>(T);
typedef FnB = U Function<U>(U);
typedef FnDynamic = T Function<T extends dynamic>(T);
typedef FnObject = T Function<T extends Object?>(T);
typedef NullableObject = Object?;
typedef Void = void;
typedef Rec = (int, {String name});

Type reify<T>() => T;
Type nested<T>() => List<T>;
Type Function() escape<T>() =>
    () => T;

class Box<T> {
  Type type() => T;
  Type other<U>() => U;
  Type Function() closure() =>
      () => List<T>;
}

class IntBox extends Box<int> {}

class Holder {
  final Type type;
  const Holder(this.type);
}

int typeConstants() {
  const xs = <Object>[int];
  const types = <Type>[int, List<String>, Rec, FnA];
  const holder = Holder(List<int>);
  const record = (int, nested: <Type>[String]);
  var result = 0;
  if (xs[0] == int) result += 1;
  if (types[1] == List<String>) result += 2;
  if (types[2] == Rec) result += 4;
  if (types[3] == FnB) result += 8;
  if (holder.type == Ints) result += 16;
  if (record.$1 == int && record.nested[0] == String) result += 32;
  return result;
}

int typeBoundaries() {
  var result = 0;
  if (dynamic != NullableObject) result += 1;
  if (dynamic != Void) result += 2;
  if (Void != NullableObject) result += 4;
  if (List<dynamic> != List<Object?>) result += 8;
  if (FnA == FnB) result += 16;
  if (FnDynamic != FnObject) result += 32;
  if (RawBound == List<num>) result += 64;
  if (Ints == List<int>) result += 128;
  return result;
}

int typeRuntime() {
  final box = IntBox();
  final escaped = escape<String>();
  final closed = box.closure();
  var result = 0;
  if (reify<int>() == int) result += 1;
  if (nested<String>() == List<String>) result += 2;
  if (box.type() == int) result += 4;
  if (box.other<String>() == String) result += 8;
  if (escaped() == String) result += 16;
  if (closed() == List<int>) result += 32;
  if (identical(reify<int>(), int)) result += 64;
  return result;
}

int typeCollections() {
  final first = reify<int>();
  final values = <Type, int>{int: 1, String: 2};
  values[first] = 3;
  final keys = <Type>{int, first, String};
  Object object = first;
  Type? nullable = object as Type;
  var result = values.length + values[int]! + keys.length;
  if (object is Type) result += 8;
  if (nullable == int) result += 16;
  if (first.hashCode == (int).hashCode) result += 32;
  return result;
}

int typeChecks(Object? value) {
  var result = 0;
  if (value is Type) result += 1;
  if (value is Type?) result += 2;
  try {
    final cast = value as Type?;
    if (cast == null) result += 4;
  } on TypeError {
    result += 8;
  }
  return result;
}

int typeCheckCalls() => typeChecks(int) + typeChecks(null) + typeChecks(42);

class HashOverride {
  @override
  // This fixture specifically tests Object.hashCode virtual dispatch.
  // ignore: hash_and_equals
  int get hashCode => 37;
}

int objectHash(Object value) => value.hashCode;
int typeHashDispatch() => objectHash(HashOverride());
