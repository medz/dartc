// ignore_for_file: use_primary_constructors, annotate_overrides, unnecessary_type_name_in_constructor
// Reversed source order exercises planning before constructor virtual dispatch.
class Child extends Middle {
  Object? direct() => super.f();
  dynamic extracted() => super.f;
}

abstract class Middle extends Original {
  Object? f([covariant num x = 20]);
  Object? originalDefault() => super.f();
}

class Original implements Contract {
  Object? value;
  Original() {
    value = f();
  }
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

abstract class Contract {
  Object? f([num x = 10]);
}

class Concrete extends Original {
  Object? f([covariant num x = 30]);
}

abstract class Extra {
  Object? f([covariant num x = 40]);
}

class InterfaceChild extends Original implements Extra {}

class Real {
  Object? f([num x = 10]) => x;
}

abstract class RealMiddle extends Real {
  Object? f([covariant num x = 20]);
}

class RealChild extends RealMiddle {}

class RealConcrete extends Real {
  Object? f([covariant num x = 30]);
}

class OwnReal extends Middle {
  Object? f([num x = 60]) => x + 1;
}

Object? ownWrapper(int form) {
  if (form == 0) return Child().value;
  if (form == 1) return Child().direct();
  if (form == 2) return Child().extracted()();
  if (form == 3) return Child().originalDefault();
  if (form == 4) return Concrete().f();
  if (form == 5) return InterfaceChild().f();
  if (form == 6) return RealChild().f();
  if (form == 7) return RealConcrete().f();
  if (form == 8) return OwnReal().f();
  dynamic object = form == 9 ? Child() : Concrete();
  return object.f is Object? Function([Object?]);
}

abstract class NamedContract {
  String f({num x = 10, num y = 11});
}

class NamedOriginal implements NamedContract {
  dynamic noSuchMethod(Invocation i) =>
      '${i.namedArguments[#x]}:${i.namedArguments[#y]}';
}

abstract class NamedMiddle extends NamedOriginal {
  String f({num y = 21, covariant num x = 20});
}

abstract class NamedLatest extends NamedMiddle {
  String f({num x = 30, covariant num y = 31});
}

class NamedChild extends NamedLatest {}

class NamedEqual extends NamedLatest {
  String f({num x = 40, num y = 41});
}

class NamedChanged extends NamedLatest {
  String f({num x = 50, num y = 51, num z = 52});
}

Object? namedWrapper(int form, Object? value) {
  dynamic object = form < 2
      ? NamedChild()
      : form == 2
      ? NamedEqual()
      : NamedChanged();
  dynamic f = object.f;
  if (form == 0) return f(x: value, y: 7);
  if (form == 1) return f is String Function({Object? x, Object? y});
  return f();
}

abstract class GenericContract<T> {
  Object? f<U extends T>([num x = 10]);
}

class GenericOriginal<T> implements GenericContract<T> {
  dynamic noSuchMethod(Invocation i) =>
      '${i.typeArguments}:${i.positionalArguments}';
}

abstract class GenericMiddle<T> extends GenericOriginal<T> {
  Object? f<U extends T>([covariant num x = 20]);
}

class GenericChild extends GenericMiddle<int> {}

class GenericEqual<T> extends GenericOriginal<T> {
  Object? f<U extends T>([covariant num x = 30]);
}

Object? genericWrapper(int form, Object? value) {
  dynamic object = form < 3 ? GenericChild() : GenericEqual<int>();
  dynamic f = object.f;
  if (form == 0 || form == 3) return f();
  if (form == 1 || form == 4) return f<int>(value);
  return f<String>(value);
}

abstract class VoidContract {
  void f([num x = 10]);
}

class VoidOriginal implements VoidContract {
  dynamic noSuchMethod(Invocation i) => i.positionalArguments[0];
}

abstract class VoidMiddle extends VoidOriginal {
  void f([covariant num x = 20]);
}

class VoidChild extends VoidMiddle {}

abstract class NeverContract {
  Never f([num x = 10]);
}

class NeverOriginal implements NeverContract {
  dynamic noSuchMethod(Invocation i) => throw (i.positionalArguments[0] as num);
}

abstract class NeverMiddle extends NeverOriginal {
  Never f([covariant num x = 20]);
}

class NeverChild extends NeverMiddle {}

Object? resultWrapper(int form) {
  dynamic object = form == 0 ? VoidChild() : NeverChild();
  return object.f();
}

class SpecializedReal {
  Object? f([covariant int? x = 10]) => x;
}

abstract class SpecializedInterface<T> {
  Object? f([T? x]);
}

abstract class SpecializedMiddle extends SpecializedReal
    implements SpecializedInterface<int> {
  Object? f([int? x = 20]);
}

class SpecializedChild extends SpecializedMiddle {}

class BoundReal {
  Object? f<U extends Object?>([num x = 10]) => x;
}

abstract class BoundInterface<T> {
  Object? f<U extends T>([num x = 40]);
}

abstract class BoundMiddle extends BoundReal
    implements BoundInterface<Object?> {
  Object? f<U extends Object?>([num x = 20]);
}

class BoundChild extends BoundMiddle {}

Object? provenanceWrapper(int form) =>
    form == 0 ? SpecializedChild().f() : BoundChild().f();
