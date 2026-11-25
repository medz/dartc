import 'dart:math';

void main() {
  print(max(1, 2)); // expect: 2
  print(min(1.5, 2)); // expect: 1.5
  print(pow(2, 10)); // expect: 1024
  print(pow(2.5, 2)); // expect: 6.25
  print(pow(2, -1)); // expect: 0.5
  print(sqrt(2)); // expect: 1.4142135623730951
  print(pi); // expect: 3.141592653589793
  print(sin(1).toStringAsFixed(12)); // expect: 0.841470984808
  print(cos(1).toStringAsFixed(12)); // expect: 0.540302305868
  print(tan(1).toStringAsFixed(12)); // expect: 1.557407724655
  print(atan2(1, 2).toStringAsFixed(12)); // expect: 0.463647609001
  print(exp(1).toStringAsFixed(12)); // expect: 2.718281828459
  print(log(10).toStringAsFixed(12)); // expect: 2.302585092994
  print(asin(0.5).toStringAsFixed(12)); // expect: 0.523598775598
  print(acos(0.5).toStringAsFixed(12)); // expect: 1.047197551197
  print(atan(0.5).toStringAsFixed(12)); // expect: 0.463647609001
  final r = Random(42);
  print([
    for (var i = 0; i < 5; i++) r.nextInt(100),
  ]); // expect: [87, 58, 4, 85, 77]
  print(r.nextDouble()); // expect: 0.5996719615235281
  print(r.nextBool()); // expect: false
  print(Point(1, 2) + Point(3, 4)); // expect: Point(4, 6)
  print(Point(1, 2).distanceTo(Point(4, 6))); // expect: 5.0
  print(Rectangle(0, 0, 10, 20).containsPoint(Point(5, 5))); // expect: true
  print(Random().nextInt(10) < 10); // expect: true
  print(Rectangle(0, 0, 10, 20)); // expect: Rectangle (0, 0) 10 x 20
  print([3, 1, 2]..shuffle(Random(1))); // expect: [2, 1, 3]
  print(max(double.nan, 1)); // expect: NaN
  print(min(-0.0, 0.0)); // expect: -0.0
}
