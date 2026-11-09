// ignore_for_file: use_primary_constructors
import 'effects.dart';

class Plain<T> {}

class Bare extends Plain<int> {
  bool same() => super.toString == toString;
}

class Named extends Plain<int> {
  @override
  String toString() {
    tick(1);
    return 'named';
  }

  String base() => super.toString();
  String Function() baseTearOff() => super.toString;
}

class Child extends Named {
  @override
  String toString() => 'child';
  String parent() => super.toString();
  String Function() parentTearOff() => super.toString;
}

class TypeOverride {
  @override
  Type get runtimeType => int;
}

String objectText(Object? value) => value.toString();
String genericText<T>(T value) => value.toString();
String Function() genericTearOff<T>(T value) => value.toString;
String extractedText(Object? value) {
  final text = value.toString;
  return text();
}

String plainStrings() =>
    Plain<int>().toString() +
    objectText(Plain<String>()) +
    genericText<Object>(Plain<bool>()) +
    extractedText(Plain<double>()) +
    objectText(TypeOverride());

String overrideStrings() =>
    objectText(Named()) + genericText<Object>(Named()) + extractedText(Named());

String superStrings() =>
    Named().base() +
    Named().baseTearOff()() +
    Child().parent() +
    Child().parentTearOff()();

String scalarStrings() =>
    objectText(null) +
    objectText(12) +
    genericText<num>(1.5) +
    extractedText(true) +
    extractedText('text');

int tearOffIdentity() {
  Object value = Plain<int>();
  final first = value.toString;
  final second = value.toString;
  final Object(toString: pattern) = value;
  dynamic erased = value;
  final dynamicMethod = erased.toString;
  final genericMethod = genericTearOff<Object>(value);
  return (first == second ? 1 : 0) +
      (first == pattern ? 2 : 0) +
      (Bare().same() ? 4 : 0) +
      (first == dynamicMethod ? 8 : 0) +
      (first == genericMethod ? 16 : 0);
}

String patternString() {
  Object value = Named();
  final Object(toString: text) = value;
  return text();
}

String functionString() => objectText(objectText);
String setString() => objectText(<int>{1});
String mapString() => extractedText(<int, int>{1: 2});

enum Choice { first }

String enumStrings() => objectText(Choice.first) + extractedText(Choice.first);

String recordString() => objectText((1, name: 'x'));
String listString() => objectText(<Object>[objectText]);
String errorString() {
  try {
    Object value = 'x';
    return objectText(value as int);
  } on TypeError catch (error) {
    return objectText(error);
  }
}

bool overrideTearOffIdentity() {
  final value = Named();
  Object object = value;
  dynamic erased = value;
  final Object(toString: pattern) = object;
  return value.toString == object.toString &&
      value.toString == genericTearOff<Object>(object) &&
      value.toString == erased.toString &&
      value.toString == pattern &&
      value.baseTearOff() != value.toString;
}

String sdkStorageString() => objectText(const MapEntry<int, String>(1, 'x'));

class Marker implements Symbol {}

bool symbolTearOffIdentity() {
  Object value = Marker();
  dynamic erased = value;
  final Object(toString: pattern) = value;
  return value.toString == erased.toString && value.toString == pattern;
}

String sdkStoragePattern() {
  Object value = const MapEntry<int, String>(1, 'x');
  final Object(toString: text) = value;
  return text();
}
