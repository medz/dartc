// Maps and sets.
void main() {
  final numbers = <int, int>{};
  for (var i = 0; i < 1000000; i++) {
    final key = i * 7919 % 100003;
    numbers[key] = (numbers[key] ?? 0) + i;
  }
  var sum = 0;
  numbers.forEach((key, value) => sum ^= key * value);
  print('${numbers.length} $sum');
  final seen = <String>{};
  for (var i = 0; i < 300000; i++) {
    seen.add('key${i % 5000}');
  }
  print(seen.length);
  var found = 0;
  for (var round = 0; round < 20; round++) {
    for (var i = 0; i < 100003; i++) {
      if (numbers.containsKey(i * 3)) found++;
    }
  }
  print(found);
}
