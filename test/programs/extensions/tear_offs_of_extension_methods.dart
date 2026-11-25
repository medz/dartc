extension Numbers on int {
  int plus(int other) => this + other;
  T same<T>(T value) => value;
}

extension Lists<T> on List<T> {
  bool holds(Object? value) => value is T;
}

void main() {
  final add = 3.plus;
  print(add(4)); // expect: 7
  print(add.runtimeType); // expect: (int) => int
  print([1, 2].map(10.plus).toList()); // expect: [11, 12]
  String Function(String) same = 3.same;
  print(same('s')); // expect: s
  print(3.same<int>(5)); // expect: 5
  final holds = ['a'].holds;
  print(holds('a')); // expect: true
  print(holds(1)); // expect: false
  print(holds.runtimeType); // expect: (Object?) => bool
  print(Numbers(3).plus(9)); // expect: 12
  dynamic d = add;
  print(d(1)); // expect: 4
  try {
    d('x');
  } catch (e) {
    print(e);
  }
  // expect: type 'String' is not a subtype of type 'int' of 'other'
}
