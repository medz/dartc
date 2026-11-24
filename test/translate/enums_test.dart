import 'support.dart';

void main() {
  agrees('simple enums', r'''
enum Color { red, green, blue }
enum Other { red }
const favorite = Color.blue;
String name(Color c) => switch (c) { Color.red => 'r', Color.green => 'g', Color.blue => 'b' };
void main() {
  print(Color.red); print(favorite); print(Color.values); print(Color.green.index);
  print(Color.blue.name); print(Color.red == Color.red); print(Object() == Color.red);
  print(Color.values.byName('green')); print(Color.values.asNameMap());
  try { Color.values.byName('pink'); } catch (e) { print(e); }
  for (final c in Color.values) print(name(c));
  switch (favorite) { case Color.red: print(1); case Color.blue: print(2); default: print(3); }
  final map = {Color.red: 1, Color.blue: 2}; print(map[Color.blue]); print(map);
  print(Color.red.runtimeType); print(Color.red is Enum);
  Object o = Color.green; print(o is Color); print(o is Other); print((o as Enum).index);
  dynamic d = Color.blue; print(d.index); print(d.name is String);
}
''');

  agrees('enums with members', r'''
mixin Shown { String get label; String show() => '[$label]'; }
abstract interface class Area { double get area; }
enum Shape with Shown implements Area, Comparable<Shape> {
  square(2, label: 'sq'),
  circle(1),
  ;
  const Shape(this.size, {this.label = 'none'});
  static const first = square;
  static int count = 0;
  static Shape pick(int n) { count++; return values[n % values.length]; }
  factory Shape.of(String s) => s == 'c' ? circle : square;
  final double size;
  @override final String label;
  @override double get area => size * size;
  Shape get next => values[(index + 1) % values.length];
  @override int compareTo(Shape other) => index - other.index;
  Shape operator +(int n) => values[(index + n) % values.length];
}
enum Kind<T extends Object> {
  text<String>('a'), number<int>(1), any<Object>(2.5);
  const Kind(this.value);
  final T value;
  Type get type => T;
  bool fits(Object o) => o is T;
  List<T> list() => [value];
}
enum Named { a, b; @override String toString() => 'Named:$name'; }
void main() {
  for (final s in Shape.values) { print(s); print(s.area); print(s.show()); print(s.next); }
  print(Shape.first); print(Shape.pick(3)); print(Shape.count); print(Shape.of('c').label);
  Area a = Shape.square; print(a.area);
  print(Shape.square.compareTo(Shape.circle)); print(Shape.square + 1);
  for (final k in Kind.values) { print(k); print(k.type); print(k.fits('s')); print(k.list().runtimeType); }
  print(Kind.text.runtimeType); print(Kind.number is Kind<num>);
  print(Named.a); print('${Named.b}'); print(Named.b.name);
  print(Shape.values.length); print(identical(Shape.of('x'), Shape.first));
  print([Shape.circle, Shape.square]..sort());
  print(Enum.compareByName(Named.b, Named.a));
}
''');
}
