// ignore_for_file: unnecessary_type_check
mixin Foreign {
  int _value() => 41;
  int foreignValue() => _value();
  int Function() foreignTearoff() => _value;
}

int callForeign(Foreign value) => value._value();
bool isForeign(Object value) => value is Foreign;

class ForeignBase() {
  int _inherited(int value) => value + 1;
  int inherited(int value) => _inherited(value);
}

abstract class ForeignRequired() {
  int _required(int value);
}

int callRequired(ForeignRequired receiver, int value) =>
    receiver._required(value);
