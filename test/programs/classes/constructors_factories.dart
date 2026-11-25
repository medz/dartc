abstract class Shape {
  factory Shape(int sides) {
    if (sides == 4) return Square(2);
    return Other();
  }
  factory Shape.big() => Square(9);
  int area();
}

class Square implements Shape {
  final int n;
  Square(this.n);
  @override
  int area() => n * n;
}

class Other implements Shape {
  @override
  int area() => 1;
}

void main() {
  number(Shape(4).area()); // expect: 4
  number(Shape(3).area()); // expect: 1
  number(Shape.big().area()); // expect: 81
}

void number(int n) => print(n);
