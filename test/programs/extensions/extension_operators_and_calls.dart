class Point {
  int x, y;
  Point(this.x, this.y);
  String toString() => '($x, $y)';
}

extension on Point {
  Point operator +(Point other) => Point(x + other.x, y + other.y);
  Point operator -() => Point(-x, -y);
  bool operator <(Point other) => x < other.x;
  int operator [](int i) => i == 0 ? x : y;
  void operator []=(int i, int value) {
    if (i == 0) {
      x = value;
    } else {
      y = value;
    }
  }

  Point call(int by) => Point(x * by, y * by);
  int get sum => x + y;
  set sum(int value) => x = value - y;
}

extension Next on int {
  int operator ~() => this + 1000;
  Iterable<int> upTo(int end) => [for (var i = this; i <= end; i++) i];
}

void main() {
  var p = Point(1, 2);
  print(p + Point(3, 4)); // expect: (4, 6)
  print(-p); // expect: (-1, -2)
  print(p < Point(2, 0)); // expect: true
  p += Point(10, 10);
  print(p); // expect: (11, 12)
  print(p[0]); // expect: 11
  p[1] = 5;
  print(p); // expect: (11, 5)
  p[0] += 3;
  print(p); // expect: (14, 5)
  print(p[1]++); // expect: 5
  print(p); // expect: (14, 6)
  p.sum = 50;
  print(p); // expect: (44, 6)
  p.sum += 4;
  print(p); // expect: (48, 6)
  print(p.sum++); // expect: 54
  print(p.sum); // expect: 55
  print(p(2)); // expect: (98, 12)
  print(p.call(3)); // expect: (147, 18)
  Point Function(int) f = p.call;
  print(f(1)); // expect: (49, 6)

  for (final i in 3.upTo(5)) print(i);
  // expect: 3
  // expect: 4
  // expect: 5
  Point? none = p.x < 0 ? p : null;
  print(none?[0]); // expect: null
  none?[0] = 2;
  print(none?.sum); // expect: null
  none?.sum += 1;
  print((none ?? p).sum); // expect: 55
  void Function() late = () => print(p.sum);
  p.x = 0;
  late(); // expect: 6
}
