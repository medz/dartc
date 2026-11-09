// @dart = 3.12
class Item {
  final int n;
  Item([this.n = 8]);
}

class Empty {}

class Hidden {
  int _read() => 3;
  int via() => _read();
}
