class A {
  final int n;
  const A(this.n);
  int twice() => n * 2;
  int get more => n + 1;
  @override
  bool operator ==(Object other) => true;
  @override
  int get hashCode => 0;
}

abstract class Shape {
  const Shape();
  int area();
}

class Square extends Shape {
  final int side;
  const Square(this.side);
  int area() => side * side;
}

class Box implements Shape {
  const Box();
  int area() => 1;
}

const Shape s = Square(4);
int area(Shape shape) => shape.area();
void main() {
  number(const A(3).twice()); // expect: 6
  number(const A(3).more); // expect: 4
  truth(const A(3) == const A(4)); // expect: true
  number(area(s)); // expect: 16
  number(area(const Box())); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);
