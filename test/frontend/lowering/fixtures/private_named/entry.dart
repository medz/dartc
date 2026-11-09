import 'declarations.dart';

class Child extends Box {
  new({super.value});
  new override({super.value = 7});
}

int direct() =>
    Box().value +
    Box(value: 2).value +
    Box.required(value: 4).value +
    Primary().value +
    Primary(value: 6).value;
int forwarded() =>
    Child().value +
    Child(value: 2).value +
    Child.override().value +
    Child.override(value: 4).value;
int tearoffs() {
  final Box Function({int value}) box = Box.new;
  final Primary Function({int value}) primary = Primary.new;
  final Child Function({int value}) child = Child.new;
  return box().value +
      box(value: 2).value +
      primary().value +
      primary(value: 6).value +
      child().value +
      child(value: 8).value;
}

int dynamicCalls() {
  dynamic box = Box.new;
  Function primary = Primary.new;
  dynamic child = Child.override;
  return box().value +
      box(value: 2).value +
      primary().value +
      primary(value: 6).value +
      child().value +
      child(value: 8).value;
}

Object? privateKey() {
  dynamic box = Box.new;
  return box(_value: 2);
}

Object? missingRequired() {
  dynamic box = Box.required;
  return box();
}
