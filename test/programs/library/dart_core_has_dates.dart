void main() {
  final d = DateTime.utc(2024, 2, 29, 12, 30, 45, 123, 456);
  print(d); // expect: 2024-02-29 12:30:45.123456Z
  print(d.toIso8601String()); // expect: 2024-02-29T12:30:45.123456Z
  print(d.weekday); // expect: 4
  print(d.add(Duration(days: 1))); // expect: 2024-03-01 12:30:45.123456Z
  print(d.millisecondsSinceEpoch); // expect: 1709209845123
  print(
    DateTime.parse('2020-01-02T03:04:05Z'),
  ); // expect: 2020-01-02 03:04:05.000Z
  print(d.difference(DateTime.utc(2024))); // expect: 1428:30:45.123456
  print(d.isBefore(DateTime.utc(2025))); // expect: true
  print(
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  ); // expect: 1970-01-01 00:00:00.000Z
  print(DateTime.now().year > 2000); // expect: true
  final s = Stopwatch()..start();
  print(s.elapsedMicroseconds >= 0); // expect: true
  print(DateTime(2024, 6, 1, 10).hour); // expect: 10
  print(d == DateTime.utc(2024, 2, 29, 12, 30, 45, 123, 456)); // expect: true
  print(d.compareTo(DateTime.utc(2000))); // expect: 1
  print(DateTime(2024, 7).timeZoneName.isNotEmpty); // expect: true
}
