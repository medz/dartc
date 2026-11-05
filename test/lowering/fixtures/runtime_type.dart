// ignore_for_file: use_primary_constructors, unnecessary_type_check
import 'effects.dart';

typedef IntFunction = int Function(int);
typedef NamedRecord = (int, {String name});

class Box<T> {}

class Derived extends Box<int> {}

class Override {
  @override
  Type get runtimeType {
    tick(1);
    return String;
  }
}

Type objectType(Object? value) => value.runtimeType;
Type genericType<T>(T value) => value.runtimeType;
Type? optionalType(Object? value) => value?.runtimeType;

int staticRuntimeTypes() {
  Box<num> box = Box<int>();
  Object derived = Derived();
  num number = 4;
  var result = 0;
  if (box.runtimeType == Box<int>) result += 1;
  if (derived.runtimeType == Derived) result += 2;
  if (number.runtimeType == int) result += 4;
  if (objectType(null) == Null) result += 8;
  if (genericType<Object>(Box<String>()) == Box<String>) result += 16;
  if (optionalType(null) == null) result += 32;
  if (optionalType(box) == Box<int>) result += 64;
  if ('value'.runtimeType == String && true.runtimeType == bool) result += 128;
  return result;
}

int identity(int value) => value;
int shapedRuntimeTypes() {
  Function function = identity;
  Record record = (1, name: 'x');
  List<num> list = <int>[1];
  var result = 0;
  if (function.runtimeType == IntFunction) result += 1;
  if (record.runtimeType == NamedRecord) result += 2;
  if (list.runtimeType == List<int>) result += 4;
  return result;
}

int overriddenRuntimeType() {
  final override = Override();
  Object object = override;
  return (object.runtimeType == String ? 1 : 0) +
      (override.runtimeType == String ? 2 : 0) +
      (genericType<Object>(override) == String ? 4 : 0) +
      (optionalType(object) == String ? 8 : 0);
}

int runtimeTypePattern(bool overridden) {
  Object value = overridden ? Override() : Box<int>();
  return switch (value) {
    Object(runtimeType: == int) => 1,
    Object(runtimeType: == String) => 2,
    Object(runtimeType: == Box<int>) => 3,
    _ => 4,
  };
}

int runtimeTypeWildcard() {
  Object value = Override();
  final Object(runtimeType: _) = value;
  return 1;
}

Type setRuntimeType() => <int>{1}.runtimeType;
Type mapRuntimeType() => <int, int>{1: 2}.runtimeType;
Type errorRuntimeType() {
  try {
    Object value = 'x';
    return (value as int).runtimeType;
  } on TypeError catch (error) {
    return error.runtimeType;
  }
}

class Base {
  Type actual() => super.runtimeType;
  Type Function() captured() =>
      () => super.runtimeType;
  @override
  Type get runtimeType => String;
}

class Child extends Base {}

class ParentOverride {
  @override
  Type get runtimeType {
    tick(2);
    return int;
  }
}

class ChildOverride extends ParentOverride {
  @override
  Type get runtimeType => String;
  Type inherited() => super.runtimeType;
}

bool superRuntimeType() {
  final value = Child();
  return value.actual() == Child &&
      value.captured()() == Child &&
      value.runtimeType == String &&
      ChildOverride().inherited() == int;
}
