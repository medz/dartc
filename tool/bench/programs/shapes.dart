// Calls of members that classes implement differently, and tests of classes.
abstract class Shape {
  int get area;
  Shape scaled(int by);
}

class Square implements Shape {
  final int side;
  Square(this.side);
  int get area => side * side;
  Shape scaled(int by) => Square(side * by % 100);
}

class Box implements Shape {
  final int width, height;
  Box(this.width, this.height);
  int get area => width * height;
  Shape scaled(int by) => Box(width * by % 100, height + by);
}

class Line extends Shape {
  int get area => 0;
  Shape scaled(int by) => by.isEven ? Square(by) : this;
}

void main() {
  final shapes = <Shape>[
    for (var i = 0; i < 1000; i++)
      switch (i % 3) {
        0 => Square(i % 50),
        1 => Box(i % 30, i % 40),
        _ => Line(),
      },
  ];
  var sum = 0;
  for (var round = 0; round < 30000; round++) {
    final at = round % 1000;
    shapes[at] = shapes[at].scaled(round % 7);
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      sum += shape.area;
      if (shape is Box) sum += shape.height;
    }
  }
  print(sum);
}
