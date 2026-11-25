void main() {
  final d = Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4);
  print(d); // expect: 1:02:03.004000
  print(d.inSeconds); // expect: 3723
  print(d + Duration(days: 1)); // expect: 25:02:03.004000
  print(d * 2); // expect: 2:04:06.008000
  print(d < Duration(hours: 2)); // expect: true
  print(-d); // expect: -1:02:03.004000
  print(d.compareTo(Duration.zero)); // expect: 1
  print(
    {d: 1}[Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4)],
  ); // expect: 1
}
