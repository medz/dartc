part 'with_method.dart';

enum WithField {
  item(1, 2, 3);

  const WithField(this._name, this._name$dartc, this._name$dartc0);

  final int _name, _name$dartc, _name$dartc0;
}

mixin Names {
  int _name$dartc() => 5;
}

void main() {
  const field = WithField.item;
  print((
    field.name,
    field._name,
    field._name$dartc,
    field._name$dartc0,
  )); // expect: (item, 1, 2, 3)
  const method = WithMethod.item;
  print((
    method.name,
    method._name,
    method._name$dartc(),
  )); // expect: (item, 4, 5)
}
