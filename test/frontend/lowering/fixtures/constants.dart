// ignore_for_file: overridden_fields, use_super_parameters, dead_code, unnecessary_type_check, unnecessary_null_aware_spreads, unnecessary_type_name_in_constructor, use_primary_constructors, use_declaring_parameters

import 'constants_private.dart';
import 'effects.dart';

class Box<T> {
  final T value;
  const Box(this.value);
  const Box.other(T input) : value = input;
  T get read => value;
}

class Child<T> extends Box<List<T>> {
  final T extra;
  const Child(super.value, this.extra);
}

class Shadow extends Box<int> {
  @override
  final int value;
  const Shadow(int inherited, this.value) : super(inherited);
  int get inherited => super.value;
}

class PrivateChild extends PrivateBase<int> {
  final int _value;
  const PrivateChild(int inherited, this._value) : super(inherited);
  int get childValue => _value;
}

abstract class Factory<T> {
  const factory Factory(T value) = Product<T>;
  T get value;
}

class Product<T> implements Factory<T> {
  @override
  final T value;
  const Product(this.value);
}

typedef IntBox = Box<int>;

class Equal {
  final int value;
  const Equal(this.value);
  @override
  bool operator ==(Object other) =>
      other is Equal && value % 2 == other.value % 2;
  @override
  int get hashCode => value % 2;
}

class GetterBox extends Box<int> {
  const GetterBox(super.value);
  @override
  int get read => tick(value + 1);
}

T identity<T>(T value) => value;
const functionAlias = identity<int>;
const functionBox = Box<int Function(int)>(functionAlias);
const listConstant = <int>[3, 1, 2];
const setConstant = <int>{3, 1, 2};
const mapConstant = <int, int>{3: 30, 1: 10, 2: 20};

bool importedConstructorAlias() =>
    identical(privateIntMaker, privateMaker<int, String>) &&
    !identical(privateIntMaker, privateMaker<int, bool>);

int collectionTypes() {
  final Object list = listConstant;
  final Object set = setConstant;
  final Object map = mapConstant;
  return (list is List<int> ? 1 : 0) +
      (list is List<String> ? 2 : 0) +
      (set is Set<int> ? 4 : 0) +
      (set is Set<String> ? 8 : 0) +
      (map is Map<int, int> ? 16 : 0) +
      (map is Map<String, int> ? 32 : 0);
}

int collectionOrder() {
  var result = 0;
  for (final value in listConstant) {
    result = result * 10 + value;
  }
  for (final value in setConstant) {
    result = result * 10 + value;
  }
  result =
      result * 1000 + mapConstant[3]! * 10 + mapConstant[1]! + mapConstant[2]!;
  return result;
}

int collectionEmptyNested() {
  const emptyList = <int>[];
  const emptySet = <int>{};
  const emptyMap = <int, int>{};
  const nested = <List<int>>[
    emptyList,
    listConstant,
    <int>[8],
  ];
  return emptyList.length +
      emptySet.length +
      emptyMap.length +
      nested[1][2] * 10 +
      nested[2][0];
}

int collectionControl() {
  const List<int>? absent = null;
  const Map<int, int>? absentMap = null;
  const values = <int>[if (true) 1 else 9, ...listConstant, ...?absent];
  const valuesSet = <int>{if (false) 9 else 4, ...setConstant, ...?absent};
  const valuesMap = <int, int>{if (true) 4: 40, ...mapConstant, ...?absentMap};
  return values.length * 100 + valuesSet.length * 10 + valuesMap.length;
}

int objectFields() {
  const child = Child<int>(<int>[2, 3], 4);
  const shadow = Shadow(5, 7);
  const private = PrivateChild(11, 13);
  final Object erased = child;
  return child.value[1] +
      child.extra +
      shadow.value * 10 +
      shadow.inherited * 100 +
      private.baseValue * 1000 +
      private.childValue * 10000 +
      (erased is Box<List<int>> ? 1000000 : 0) +
      (erased is Child<String> ? 2000000 : 0);
}

bool canonicalObjects() =>
    identical(const Box<int>(1), const Box<int>.other(1)) &&
    identical(const IntBox(1), const Box<int>(1)) &&
    identical(const Factory<int>(1), const Product<int>(1)) &&
    !identical(Box<int>(1), Box<int>(1)) &&
    !identical(Box<int>(1), const Box<int>(1));
int defaultObject([
  Box<int> value = const Box<int>(6),
  List<int> list = const <int>[7],
]) => value.value * 10 + list[0];
int redirectedAndDefaults() =>
    const Factory<int>(9).value * 100 + defaultObject();
int constantPatterns(bool derived) {
  final Box<int> value = derived ? const GetterBox(4) : const Box<int>(4);
  return switch (value) {
    Box<int>(read: final read, value: final raw) => read * 10 + raw,
  };
}

int equalityVersusIdentity() {
  const a = Equal(1);
  const b = Equal(3);
  return (a == b ? 1 : 0) +
      (identical(a, b) ? 2 : 0) +
      (identical(const Box<num>(1), const Box<num>(1.0)) ? 4 : 0) +
      (identical(const Box<double>(0.0), const Box<double>(-0.0)) ? 8 : 0) +
      (identical(const Box<num>(1), const Box<int>(1)) ? 16 : 0);
}

bool canonicalCollections() =>
    identical(const <int>[1], const <int>[1]) &&
    identical(const <int>{1}, const <int>{1}) &&
    identical(const <int, int>{1: 2}, const <int, int>{1: 2}) &&
    !identical(const <num>[1], const <num>[1.0]) &&
    !identical(const <double>[0.0], const <double>[-0.0]) &&
    !identical(const <int>[1], const <num>[1]);
int embeddedFunctions(int value) {
  const functions = <int Function(int)>[functionAlias];
  const boxes = <Box<int Function(int)>>[functionBox];
  return functions[0](value) +
      boxes[0].value(value + 1) +
      functionBox.value(value + 2);
}

class SourceCursor implements Iterator<int> {
  int step = 0;
  @override
  int get current => tick(30);
  @override
  bool moveNext() {
    tick(20);
    return step++ == 0;
  }
}

class Source implements Iterable<int> {
  @override
  Iterator<int> get iterator {
    tick(10);
    return SourceCursor();
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int listMutation(int operation) {
  final List<num> values = const <int>[1];
  tick(1);
  switch (operation) {
    case 0:
      values.addAll(<int>[]);
    case 1:
      values.addAll(Source());
    case 2:
      values.add(1.5);
    case 3:
      values[99] = 1.5;
    case 4:
      values[99] = 2;
    case 5:
      values[0] = 1;
  }
  return tick(2);
}

int setMutation(int operation) {
  final Set<num> values = const <int>{1};
  tick(1);
  switch (operation) {
    case 0:
      values.add(1);
    case 1:
      values.addAll(<int>[]);
    case 2:
      values.addAll(Source());
    case 3:
      values.add(1.5);
  }
  return tick(2);
}

int mapMutation(int operation) {
  final Map<num, num> values = const <int, int>{1: 2};
  tick(1);
  switch (operation) {
    case 0:
      values[1] = 2;
    case 1:
      values[1.5] = 2;
    case 2:
      values[1] = 2.5;
    case 3:
      values.addAll(<int, int>{});
  }
  return tick(2);
}

int listReadBounds() => listConstant[tick(99)];

class Pair<A, B> {
  final A first;
  final B second;
  const Pair(this.first, this.second);
}

typedef Flip<A, B> = Pair<B, A>;
const aliasMake = Flip<int, String>.new;
const aliasList = <Pair<String, int> Function(String, int)>[aliasMake];
const aliasSet = <Pair<String, int> Function(String, int)>{aliasMake};
const aliasMap = <int, Pair<String, int> Function(String, int)>{1: aliasMake};
const aliasObject = Box<Pair<String, int> Function(String, int)>(aliasMake);

class AliasHolder {
  final Pair<String, int> Function(String, int) make;
  const AliasHolder([this.make = aliasMake]);
}

class AliasInitializer {
  final Pair<String, int> Function(String, int) make = aliasMake;
  const AliasInitializer();
}

int embeddedAliasConstructors(int value) {
  var result = aliasList[0]('a', value).second;
  for (final make in aliasSet) {
    result += make('b', value + 1).second;
  }
  result += aliasMap[1]!('c', value + 2).second;
  result += aliasObject.value('d', value + 3).second;
  result += const AliasHolder().make('e', value + 4).second;
  result += const AliasInitializer().make('f', value + 5).second;
  return result;
}

int constantEqualityPattern(int value) {
  final candidate = Equal(value);
  return switch (candidate) {
    const Equal(1) => 10,
    const Equal(2) => 20,
    _ => 30,
  };
}

bool orderedCanonicalCollections() =>
    !identical(const <int>{1, 2}, const <int>{2, 1}) &&
    !identical(const <int, int>{1: 2, 3: 4}, const <int, int>{3: 4, 1: 2}) &&
    !identical(const <int, num>{1: 1}, const <int, num>{1: 1.0});

int widenedRecordCanonicalization() {
  const (num,) wide = (1,);
  const narrow = (1,);
  const wideBox = Box<(num,)>(wide);
  const narrowBox = Box<(num,)>(narrow);
  const wideList = <(num,)>[wide];
  const narrowList = <(num,)>[narrow];
  return (identical(wideBox, narrowBox) ? 1 : 0) +
      (identical(wideList, narrowList) ? 2 : 0) +
      (wideBox.value.$1 == 1 ? 4 : 0);
}

class WideSource implements Iterable<num> {
  @override
  Iterator<num> get iterator {
    tick(10);
    return SourceCursor();
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

class WideMap implements Map<num, num> {
  @override
  void forEach(void Function(num, num) action) {
    tick(10);
    action(1, 2);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int addAllSourceType(int kind, bool immutable, bool custom) {
  tick(1);
  if (kind == 0) {
    final List<num> target = immutable ? const <int>[] : <int>[];
    target.addAll(custom ? WideSource() : <double>[]);
  } else if (kind == 1) {
    final Set<num> target = immutable ? const <int>{} : <int>{};
    target.addAll(custom ? WideSource() : <double>[]);
  } else {
    final Map<num, num> target = immutable ? const <int, int>{} : <int, int>{};
    target.addAll(custom ? WideMap() : <double, double>{});
  }
  return tick(2);
}

class DynamicCursor implements Iterator<dynamic> {
  final bool fail;
  int step = 0;
  DynamicCursor(this.fail);
  @override
  dynamic get current {
    tick(30 + step);
    return fail && step == 2 ? 'wrong' : step;
  }

  @override
  bool moveNext() {
    tick(20);
    return ++step <= 3;
  }
}

class DynamicSource implements Iterable<dynamic> {
  final bool fail;
  DynamicSource(this.fail);
  @override
  Iterator<dynamic> get iterator {
    tick(10);
    return DynamicCursor(fail);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int literalDynamicSpread(bool fail, bool asSet) {
  final Iterable<dynamic> source = DynamicSource(fail);
  final Iterable<num> values = asSet ? <num>{...source} : <num>[...source];
  return values.length;
}

bool rootObjectIdentity() => identical(const Object(), const Object());
