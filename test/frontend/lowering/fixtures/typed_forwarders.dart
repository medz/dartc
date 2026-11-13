// ignore_for_file: use_primary_constructors, annotate_overrides, unnecessary_type_check, unused_element_parameter, unnecessary_type_name_in_constructor, curly_braces_in_flow_control_structures
import 'effects.dart' as effects;

abstract class ForwardContract<A> {
  int optional([int value = 11]);
  int named(int value, {int zebra = 23, int alpha = 17});
  T generic<T extends A>(T value);
  Type defaultType<T extends A>();
  int get property;
  set property(int value);
  int call(int value, {int extra = 19});
  int operator [](int index);
  int _private([int value = 29]);
}

class ForwardBox<A> implements ForwardContract<A> {
  Invocation? last;
  dynamic answer;
  bool throwing;
  ForwardBox(this.answer, [this.throwing = false]);
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    last = invocation;
    if (throwing) throw answer as Object;
    if (invocation.memberName == #defaultType)
      return invocation.typeArguments[0];
    return answer;
  }
}

Object? forwardForms(int form) {
  final box = ForwardBox<num>(7);
  ForwardContract<num> typed = box;
  dynamic dynamicBox = box;
  Object? result;
  if (form == 0) result = typed.optional();
  if (form == 1) result = dynamicBox.optional();
  if (form == 2) result = typed.named(effects.tick(1), zebra: effects.tick(2));
  if (form == 3)
    result = dynamicBox.named(effects.tick(1), zebra: effects.tick(2));
  if (form == 4) result = typed.property;
  if (form == 5) result = dynamicBox.property;
  if (form == 6) result = typed.property = effects.tick(3);
  if (form == 7) result = dynamicBox.property = effects.tick(3);
  if (form == 8) result = typed(effects.tick(1));
  if (form == 9) result = dynamicBox(effects.tick(1));
  if (form == 10) result = typed[effects.tick(1)];
  if (form == 11) result = dynamicBox[effects.tick(1)];
  if (form == 12) result = typed._private();
  if (form == 13) result = dynamicBox._private();
  final invocation = box.last!;
  return '$result:${forwardMirror(invocation)}';
}

Object? forwardGenerics(int form) {
  final box = ForwardBox<num>(7);
  ForwardContract<num> typed = box;
  dynamic dynamicBox = box;
  if (form == 0) typed.generic<int>(effects.tick(1));
  if (form == 1) dynamicBox.generic<int>(effects.tick(1));
  if (form == 2) dynamicBox.generic(effects.tick(1));
  if (form == 3) typed.defaultType<num>();
  if (form == 4) dynamicBox.defaultType();
  if (form == 5) {
    dynamic tear = typed.generic;
    tear<int>(effects.tick(1));
  }
  final invocation = box.last!;
  return '${invocation.typeArguments.length}:${invocation.typeArguments[0] == int}:${invocation.typeArguments[0] == num}:${forwardMirror(invocation)}';
}

Object? forwardFailures(int form, dynamic bad) {
  final box = ForwardBox<num>(bad, form == 9);
  dynamic dynamicBox = box;
  if (form == 0) return dynamicBox.named(bad, zebra: effects.tick(2));
  if (form == 1) return dynamicBox.generic<String>('bad');
  if (form == 2) return dynamicBox.optional(effects.tick(1));
  if (form == 3) dynamicBox.optional(effects.tick(1), effects.tick(2));
  if (form == 4) dynamicBox.named(effects.tick(1), unknown: effects.tick(2));
  if (form == 5) dynamicBox.generic<int, int>(effects.tick(1));
  if (form == 6) {
    dynamic tear = dynamicBox.optional;
    return tear(effects.tick(1), effects.tick(2));
  }
  if (form == 7) return dynamicBox(effects.tick(1), unknown: effects.tick(2));
  if (form == 8) return dynamicBox.optional(effects.tick(-1));
  if (form == 9) {
    try {
      dynamicBox.optional(effects.tick(1));
    } catch (error) {
      return identical(error, bad);
    }
  }
  final invocation = box.last!;
  return forwardMirror(invocation);
}

abstract class VoidContract {
  void method();
  void get getter;
  void field;
  set setter(int value);
  Never never();
}

class VoidForward implements VoidContract {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return 7;
  }
}

Object? forwardVoid(int form) {
  dynamic box = VoidForward();
  if (form == 0) return box.method();
  if (form == 1) return box.getter;
  if (form == 2) return box.field;
  if (form == 3) return box.field = effects.tick(3);
  if (form == 4) return box.setter = effects.tick(4);
  if (form == 5) {
    dynamic tear = box.method;
    return tear();
  }
  return box.never();
}

abstract class CovariantContract<T> {
  int explicit(covariant num value);
  int owner(T value);
}

class InheritedCovariant extends CovariantForward<int> {}

class CovariantForward<T> implements CovariantContract<T> {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return 7;
  }
}

Object? forwardCovariance(int form, dynamic value) {
  final box = CovariantForward<int>();
  if (form == 0) {
    dynamic tear = box.explicit;
    return tear(value);
  }
  if (form == 1) {
    dynamic tear = box.owner;
    return tear(value);
  }
  if (form == 2) return box.explicit is int Function(Object?);
  if (form == 3) return box.owner is int Function(Object?);
  final child = InheritedCovariant();
  if (form == 4) {
    dynamic dynamicChild = child;
    return dynamicChild.owner(value);
  }
  if (form == 5) {
    dynamic tear = child.owner;
    return tear(value);
  }
  return child.owner is int Function(Object?);
}

// Deliberately declare children before their ancestors.
class ReusedChild extends Redeclared {
  int directParent() => super.inherited();
  int parentTear() {
    final tear = super.inherited;
    return tear();
  }
}

abstract class Redeclared extends OriginalForward {
  int inherited([int value = 30]);
}

class OriginalForward implements InheritedContract {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return invocation.positionalArguments[0];
  }
}

abstract class InheritedContract {
  int inherited([int value = 10]);
}

class RealOverride extends OriginalForward {
  int inherited([int value = 40]) => effects.tick(value);
}

class RealChild extends RealOverride {}

abstract class RealAbstract extends RealOverride {
  int inherited([int value = 50]);
}

class RealAbstractChild extends RealAbstract {}

class NarrowChild extends NarrowAbstract {}

class NarrowBadResult extends NarrowAbstract {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return 2.5;
  }
}

abstract class NarrowAbstract extends WideForward {
  int narrowed([int value = 60]);
}

class WideForward {
  num narrowed([int value = 20]);
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return invocation.positionalArguments[0];
  }
}

Object? forwardInheritance(int form) {
  if (form == 0) {
    dynamic box = ReusedChild();
    return box.inherited();
  }
  if (form == 1) return ReusedChild().directParent();
  if (form == 2) return ReusedChild().parentTear();
  if (form == 3) {
    dynamic box = RealChild();
    return box.inherited();
  }
  if (form == 4) {
    dynamic box = RealAbstractChild();
    return box.inherited();
  }
  if (form == 5) {
    dynamic box = NarrowChild();
    return box.narrowed();
  }
  if (form == 7) {
    dynamic box = NarrowBadResult();
    return box.narrowed();
  }
  final tear = ReusedChild().inherited;
  return tear();
}

String forwardMirror(Invocation invocation) {
  var result =
      '${invocation.isMethod}:${invocation.isGetter}:${invocation.isSetter}:${invocation.typeArguments.length}';
  for (final value in invocation.positionalArguments) {
    result = '$result:$value';
  }
  for (final entry in invocation.namedArguments.entries) {
    result = '$result:${entry.key}:${entry.value}';
  }
  final named = invocation.namedArguments;
  return '$result:${named.length}:${named[#zebra]}:${named[#alpha]}:${named[#extra]}:${named[#unknown]}';
}

Invocation forwardIdentityCall(ForwardBox<num> box, int form) {
  dynamic receiver = box;
  if (form == 0) receiver.property;
  if (form == 1) receiver.optional();
  if (form == 2) receiver.generic<int>(1);
  if (form == 3) receiver.named(1);
  if (form == 4) receiver.absent();
  return box.last!;
}

int forwardImmutability(int form, int operation) {
  final box = ForwardBox<num>(7);
  final invocation = forwardIdentityCall(box, form);
  try {
    if (operation == 0) invocation.positionalArguments.add(3);
    if (operation == 1) invocation.positionalArguments[0] = 3;
    if (operation == 2) invocation.typeArguments.add(int);
    if (operation == 3) invocation.typeArguments[0] = num;
    if (operation == 4) invocation.namedArguments[#alpha] = 99;
  } on UnsupportedError {
    return 1;
  }
  return 0;
}

abstract class NamedCovariantContract<T> {
  int reordered({required T z});
}

class NamedCovariantBase<T> implements NamedCovariantContract<T> {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return 7;
  }
}

abstract class NamedCovariantMiddle extends NamedCovariantBase<int> {
  int reordered({int a = 2, required int z});
}

class NamedCovariantChild extends NamedCovariantMiddle {}

Object? forwardNamedCovariance(int form, dynamic value) {
  final box = NamedCovariantChild();
  final tear = box.reordered;
  if (form == 0)
    return '${tear is int Function({int a, required Object? z})}:${tear is int Function({Object? a, required int z})}';
  if (form == 1) {
    dynamic fn = tear;
    return fn(z: value);
  }
  if (form == 2) {
    dynamic fn = tear;
    return fn(a: value, z: effects.tick(1));
  }
  dynamic receiver = box;
  return receiver.reordered(z: value);
}

abstract class RepeatedCovariantContract<T> {
  Object repeated(T value);
}

class RepeatedCovariantBase<T> implements RepeatedCovariantContract<T> {
  dynamic noSuchMethod(Invocation invocation) {
    effects.tick(90);
    return 7;
  }
}

abstract class RepeatedCovariantNumDeclaration
    extends RepeatedCovariantBase<int> {
  num repeated(int value);
}

class RepeatedCovariantNum extends RepeatedCovariantNumDeclaration {}

abstract class RepeatedCovariantIntDeclaration extends RepeatedCovariantNum {
  int repeated(int value);
}

class RepeatedCovariantInt extends RepeatedCovariantIntDeclaration {}

Object? forwardRepeatedCovariance(int form, dynamic value) {
  if (form == 0)
    return RepeatedCovariantNum().repeated is num Function(Object?);
  if (form == 1)
    return RepeatedCovariantInt().repeated is int Function(Object?);
  if (form == 2) {
    dynamic fn = RepeatedCovariantNum().repeated;
    return fn(value);
  }
  if (form == 3) {
    dynamic fn = RepeatedCovariantInt().repeated;
    return fn(value);
  }
  if (form == 4) {
    dynamic box = RepeatedCovariantNum();
    return box.repeated(value);
  }
  dynamic box = RepeatedCovariantInt();
  return box.repeated(value);
}

class SuperOrderChild extends SuperOrderMid<int> {
  Object run() {
    int local() => super.f<int>();
    final t = super.f;
    super.value = 17;
    return '${local()}:${t<int>()}:${super.value}:${super[3]}:${-super.self}';
  }
}

abstract class SuperOrderMid<X> extends SuperOrderParent<X> {
  T f<T extends X>([int q = 22]);
}

class SuperOrderParent<X> implements SuperOrderContract<X> {
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #self) return this;
    if (i.memberName == #value) return 12;
    if (i.memberName == const Symbol('value=')) return null;
    if (i.memberName == const Symbol('unary-')) return 6;
    return i.positionalArguments[0];
  }
}

abstract class SuperOrderContract<X> {
  T f<T extends X>([int q = 11]);
  int get value;
  set value(int x);
  int operator [](int x);
  SuperOrderContract<X> get self;
  int operator -();
}

Object forwardSuperOrder() => SuperOrderChild().run();
