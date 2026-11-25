void main() {
  final values = <int, int>{1: 42, 2: 17};
  print(values[1]! + values[2]!); // expect: 59
}
