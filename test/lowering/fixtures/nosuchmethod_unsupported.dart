// ignore_for_file: use_primary_constructors, unused_element

import 'nosuchmethod_unsupported_private.dart';

abstract class Contract<T> {
  int method<U extends num>(U value);
  T get property;
  set property(T value);
  int call(int value);
  int _private(int value);
}

class Forwarded<T> implements Contract<T> {
  @override
  dynamic noSuchMethod(Invocation invocation) => 1;
}

class ForwardedChild extends Forwarded<int> {}

abstract class Deferred implements Contract<int> {
  @override
  dynamic noSuchMethod(Invocation invocation) => 1;
}

class DeferredChild extends Deferred {}

sealed class SealedDeferred implements Contract<int> {
  @override
  dynamic noSuchMethod(Invocation invocation) => 1;
}

class SealedChild extends SealedDeferred {}

class Real extends Forwarded<int> {
  @override
  int method<U extends num>(U value) => 2;
}

class RealChild extends Real {}

abstract class AbstractRedeclaration extends Real {
  @override
  int method<U extends num>(U value);
}

class RedeclarationChild extends AbstractRedeclaration {}

class OrdinaryImplementation {
  int method(int value) => value;
}

abstract class OrdinaryRedeclaration extends OrdinaryImplementation {
  @override
  int method(int value);
}

class OrdinaryChild extends OrdinaryRedeclaration {
  @override
  dynamic noSuchMethod(Invocation invocation) => 3;
}

class DefaultPrivate implements PrivateContract {}

class CustomPrivate implements PrivateContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => 4;
}

class RealPrivate extends PrivateImplementation {}

class PartialIterable implements Iterable<int> {
  @override
  Iterator<int> get iterator => throw 'unused';

  @override
  Never noSuchMethod(Invocation invocation) => throw 'unused';
}
