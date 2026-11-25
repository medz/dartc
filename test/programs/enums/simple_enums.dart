enum Color { red, green, blue }

enum Other { red }

const favorite = Color.blue;
String name(Color c) => switch (c) {
  Color.red => 'r',
  Color.green => 'g',
  Color.blue => 'b',
};
void main() {
  print(Color.red); // expect: Color.red
  print(favorite); // expect: Color.blue
  print(Color.values); // expect: [Color.red, Color.green, Color.blue]
  print(Color.green.index); // expect: 1
  print(Color.blue.name); // expect: blue
  print(Color.red == Color.red); // expect: true
  print(Object() == Color.red); // expect: false
  print(Color.values.byName('green')); // expect: Color.green
  print(
    Color.values.asNameMap(),
  ); // expect: {red: Color.red, green: Color.green, blue: Color.blue}
  try {
    Color.values.byName('pink');
  } catch (e) {
    print(e);
  }
  // expect: Invalid argument (name): No enum value with that name: "pink"
  for (final c in Color.values) print(name(c));
  // expect: r
  // expect: g
  // expect: b
  switch (favorite) {
    case Color.red:
      print(1);
    case Color.blue:
      print(2);
    default:
      print(3);
  }
  // expect: 2
  final map = {Color.red: 1, Color.blue: 2};
  print(map[Color.blue]); // expect: 2
  print(map); // expect: {Color.red: 1, Color.blue: 2}
  print(Color.red.runtimeType); // expect: Color
  print(Color.red is Enum); // expect: true
  Object o = Color.green;
  print(o is Color); // expect: true
  print(o is Other); // expect: false
  print((o as Enum).index); // expect: 1
  dynamic d = Color.blue;
  print(d.index); // expect: 2
  print(d.name is String);
}
// stderr: Unhandled exception:
// stderr: NoSuchMethodError: Class 'Color' has no instance getter 'name'.
// stderr: Receiver: Instance of 'Color'
// stderr: Tried calling: name
// exit: 255
