extension type Id(int value) {
  Id.of(String text) : this(int.parse(text));
  Id.double(int n) : value = n * 2;
  factory Id.zero() => Id(0);
  static int made = 3;
  static Id next() => Id(made++);
  Id operator +(Id other) => Id(value + other.value);
  bool get isEven => value.isEven;
  String show([String end = '!']) => 'Id($value)$end';
}

extension type const Name._(String text) implements String {
  const Name(String text) : this._(text);
  String get loud => toUpperCase() + '!';
  int get length => 99;
}

extension type Numbers(List<int> _) implements Iterable<int> {
  void push(int n) => _.add(n);
  int operator [](int i) => _[i];
}

const name = Name('cat');
void main() {
  final id = Id(3);
  print(id.value); // expect: 3
  print(id.show()); // expect: Id(3)!
  print((id + Id.of('4')).show('?')); // expect: Id(7)?
  print(Id.double(5).value); // expect: 10
  print(Id.zero().value); // expect: 0
  print(Id.next().value); // expect: 3
  print(Id.next().value); // expect: 4
  print(id.isEven); // expect: false
  Object o = id as Object;
  print(o is int); // expect: true
  print(o is Id); // expect: true
  print(id == 3); // expect: true
  print(id.runtimeType); // expect: int
  print(<Id>[id].runtimeType); // expect: List<int>
  print(o as Id); // expect: 3
  print(name); // expect: cat
  print(name.loud); // expect: CAT!
  print(name.length); // expect: 99
  print(name.substring(1)); // expect: at
  String plain = name;
  print(plain.length); // expect: 3
  final numbers = Numbers([1, 2]);
  numbers.push(7);
  print(numbers[2]); // expect: 7
  print(numbers.length); // expect: 3
  print(numbers.map((n) => n + 1).toList()); // expect: [2, 3, 8]
  for (final n in numbers) print(n);
  // expect: 1
  // expect: 2
  // expect: 7
  Id? none = o is String ? id : null;
  print(none?.value); // expect: null
  print(none == null); // expect: true
  final make = Id.new;
  print(make(6).value); // expect: 6
  final show = id.show;
  print(show('.')); // expect: Id(3).
  Map<Id, int> map = {id: 1};
  print(map[Id(3)]); // expect: 1
}
