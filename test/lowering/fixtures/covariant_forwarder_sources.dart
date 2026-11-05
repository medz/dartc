// ignore_for_file: use_primary_constructors, annotate_overrides
// Deliberately precedes the declarations: target caching must be correct here.
Object? ownSourceCovariance(int form, Object? value) {
  dynamic p = RealOwn().f;
  dynamic n = NamedOwn().f;
  dynamic b = BoundedOwn().f;
  switch (form) {
    case 0:
      return p is Object? Function(Object?);
    case 1:
      return p(value);
    case 2:
      return RealOwnChild().f is Object? Function(Object?);
    case 3:
      return RealOriginal().f is Object? Function(Object?);
    case 4:
      return n is Object? Function({Object? z, int a});
    case 5:
      return n(z: value, a: 9);
    case 6:
      return n();
    case 7:
      return b is Object? Function<U extends num>(Object?);
    case 8:
      return b<int>(value);
    case 9:
      return b<String>(value);
    default:
      return b(value);
  }
}

class RealOriginal {
  Object? f(int value) => value;
}

class RealOwn extends RealOriginal implements Positional<int> {
  Object? f(int value) => value + 1;
}

class RealOwnChild extends RealOwn {}

class NamedOwn implements Named<int> {
  Object? f({int a = 5, int? z}) => z;
}

class BoundedOwn implements Bounded<num> {
  Object? f<U extends num>(num? value) => value;
}

abstract class Positional<T> {
  Object? f(T value);
}

class PositionalForward implements Positional<int> {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

class PositionalChild extends PositionalForward {}

class GenericForward<T> implements Positional<T> {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

abstract class Named<T> {
  Object? f({T? z, int a = 3});
}

class NamedForward implements Named<int> {
  dynamic noSuchMethod(Invocation i) => i.namedArguments[#z];
}

abstract class Bounded<T> {
  Object? f<U extends T>(T? value);
}

class BoundedForward implements Bounded<num> {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

Object? sourceCovariance(int form, Object? value) {
  dynamic p = PositionalForward().f;
  dynamic n = NamedForward().f;
  dynamic b = BoundedForward().f;
  switch (form) {
    case 0:
      return p is Object? Function(Object?);
    case 1:
      return p(value);
    case 2:
      return PositionalChild().f is Object? Function(Object?);
    case 3:
      return GenericForward<int>().f is Object? Function(Object?);
    case 4:
      return n is Object? Function({Object? z, int a});
    case 5:
      return n(z: value, a: 9);
    case 6:
      return n();
    case 7:
      return b is Object? Function<U extends num>(Object?);
    case 8:
      return b<int>(value);
    case 9:
      return b<String>(value);
    default:
      return b(value);
  }
}

class TransitiveForward implements RealOwn {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

class TransitiveNamedForward implements NamedOwn {
  dynamic noSuchMethod(Invocation i) => i.namedArguments[#z];
}

Object? transitiveSourceCovariance(int form, Object? value) {
  dynamic p = TransitiveForward().f;
  dynamic n = TransitiveNamedForward().f;
  switch (form) {
    case 0:
      return p is Object? Function(Object?);
    case 1:
      return p(value);
    case 2:
      return n is Object? Function({Object? z, int a});
    case 3:
      return n(z: value, a: 9);
    default:
      return n();
  }
}
