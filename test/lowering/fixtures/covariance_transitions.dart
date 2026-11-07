import 'covariance_transitions_private.dart' as private;

class PrivateConcrete() extends private.Real implements private.Contract;
abstract class PrivateAbstract()
    extends private.Real
    implements private.Contract;
class PrivateChild() extends PrivateAbstract;

String privateDispatch() =>
    '${private.inspectPrivate(PrivateConcrete())}:${private.inspectPrivate(PrivateChild())}';

abstract class I() {
  Object? f([num x = 10]);
}

class A() implements I {
  @override
  dynamic noSuchMethod(Invocation call) => call.positionalArguments[0];
}

abstract class J() {
  Object? f([covariant num x = 40]);
}

abstract class B() extends A implements J;
class C() extends B;

class R() {
  Object? f([num x = 10]) => x;
}

abstract class Narrow() extends R {
  @override
  Object? f([covariant int x = 20]);
}

class NarrowChild() extends Narrow;

abstract class NarrowMissing() extends A {
  @override
  Object? f([covariant int x = 20]);
}

class MissingChild() extends NarrowMissing;

class Operations() {
  num saved = 0;
  set value(num value) => saved = value;
  num operator +(num value) => value;
}

abstract class CheckedOperations() extends Operations {
  @override
  set value(covariant int value);
  @override
  num operator +(covariant int value);
}

class OperationChild() extends CheckedOperations;

Object? operations(Object? value) {
  dynamic object = OperationChild();
  object.value = value;
  return '${object.saved}:${object + value}';
}

class Explicit() {
  Object? f([covariant num? x = 10]) => x;
}

abstract class Generic<T extends num>() extends Explicit {
  @override
  Object? f([T? x]);
}

class GenericChild() extends Generic<int>;

class Concrete() {
  Object? accept(int value) => value;
}

abstract class Interface<T>() {
  Object? accept(T value);
}

class Specialized() extends Concrete implements Interface<int>;

class Bounds() {
  Object? f<T extends Object?>([num x = 10]) => x;
}

abstract class BoundInterface<T>() {
  Object? f<U extends T>([num x = 40]);
}

abstract class BoundMiddle() extends Bounds implements BoundInterface<Object?>;
class BoundChild() extends BoundMiddle;

String defaults() =>
    '${C().f()}:${NarrowChild().f()}:${GenericChild().f()}:${BoundChild().f()}:${MissingChild().f()}';

Object? call(int kind, Object? argument) {
  dynamic object = switch (kind) {
    0 => C(),
    1 => NarrowChild(),
    2 => GenericChild(),
    3 => Specialized(),
    5 => MissingChild(),
    _ => BoundChild(),
  };
  if (kind == 3) return object.accept(argument);
  return object.f(argument);
}

String tearoffs() {
  final Object a = C().f, b = NarrowChild().f, c = Specialized().accept;
  return '${a is Object? Function([Object?])}:${b is Object? Function([Object?])}:${c is Object? Function(Object?)}';
}
