// ignore_for_file: use_primary_constructors, unused_element, unused_element_parameter

abstract class PrivateContract {
  int _method([int value = 7]);
  int get _property;
  set _property(int value);
}

int invokePrivate(PrivateContract receiver) => receiver._method();

class PrivateImplementation {
  int _implemented(int value) => value;
}

abstract class ChangedPrivateImplementation extends PrivateImplementation {
  @override
  int _implemented(num value);
}

int invokeChangedPrivate(ChangedPrivateImplementation receiver) =>
    receiver._implemented(1.5);
