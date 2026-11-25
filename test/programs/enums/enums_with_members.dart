mixin Shown {
  String get label;
  String show() => '[$label]';
}

abstract interface class Area {
  double get area;
}

enum Shape with Shown implements Area, Comparable<Shape> {
  square(2, label: 'sq'),
  circle(1);

  const Shape(this.size, {this.label = 'none'});
  static const first = square;
  static int count = 0;
  static Shape pick(int n) {
    count++;
    return values[n % values.length];
  }

  factory Shape.of(String s) => s == 'c' ? circle : square;
  final double size;
  @override
  final String label;
  @override
  double get area => size * size;
  Shape get next => values[(index + 1) % values.length];
  @override
  int compareTo(Shape other) => index - other.index;
  Shape operator +(int n) => values[(index + n) % values.length];
}

enum Kind<T extends Object> {
  text<String>('a'),
  number<int>(1),
  any<Object>(2.5);

  const Kind(this.value);
  final T value;
  Type get type => T;
  bool fits(Object o) => o is T;
  List<T> list() => [value];
}

enum Named {
  a,
  b;

  @override
  String toString() => 'Named:$name';
}

void main() {
  for (final s in Shape.values) {
    print(s);
    print(s.area);
    print(s.show());
    print(s.next);
  }
  // expect: Shape.square
  // expect: 4.0
  // expect: [sq]
  // expect: Shape.circle
  // expect: Shape.circle
  // expect: 1.0
  // expect: [none]
  // expect: Shape.square
  print(Shape.first); // expect: Shape.square
  print(Shape.pick(3)); // expect: Shape.circle
  print(Shape.count); // expect: 1
  print(Shape.of('c').label); // expect: none
  Area a = Shape.square;
  print(a.area); // expect: 4.0
  print(Shape.square.compareTo(Shape.circle)); // expect: -1
  print(Shape.square + 1); // expect: Shape.circle
  for (final k in Kind.values) {
    print(k);
    print(k.type);
    print(k.fits('s'));
    print(k.list().runtimeType);
  }
  // expect: Kind.text
  // expect: String
  // expect: true
  // expect: List<String>
  // expect: Kind.number
  // expect: int
  // expect: false
  // expect: List<int>
  // expect: Kind.any
  // expect: Object
  // expect: true
  // expect: List<Object>
  print(Kind.text.runtimeType); // expect: Kind<String>
  print(Kind.number is Kind<num>); // expect: true
  print(Named.a); // expect: Named:a
  print('${Named.b}'); // expect: Named:b
  print(Named.b.name); // expect: b
  print(Shape.values.length); // expect: 2
  print(identical(Shape.of('x'), Shape.first)); // expect: true
  print(
    [Shape.circle, Shape.square]..sort(),
  ); // expect: [Shape.square, Shape.circle]
  print(Enum.compareByName(Named.b, Named.a)); // expect: 1
}
