// Functions that are values, and generic code.
class Item implements Comparable<Item> {
  final int key;
  final String name;
  Item(this.key, this.name);
  int compareTo(Item other) => key.compareTo(other.key);
}

void main() {
  var seed = 42;
  int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  final numbers = [for (var i = 0; i < 500000; i++) next()];
  final sorted = [...numbers]..sort();
  print(sorted[1000]);
  final items = [for (final n in numbers.take(200000)) Item(n % 10007, '$n')];
  items.sort();
  print(items[777].key);
  items.sort((a, b) => a.name.compareTo(b.name));
  print(items[777].name);
  var sum = 0;
  for (var round = 0; round < 20; round++) {
    sum += numbers
        .where((n) => n % 3 == round % 3)
        .map((n) => n ~/ 7)
        .fold(0, (a, b) => (a + b) & 0xffffff);
  }
  print(sum);
  print(numbers.reduce((a, b) => a > b ? a : b));
}
