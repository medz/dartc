class Box {
  final int _value;
  new({this._value = 3});
  new required({required this._value});
  int get value => _value;
}

class Primary({final int _value = 5}) {
  int get value => _value;
}

int local() => Box(value: 11).value + Primary(value: 13).value;
