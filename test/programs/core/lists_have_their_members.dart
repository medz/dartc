void main() {
  final l = <int>[3, 1, 2];
  print(l); // expect: [3, 1, 2]
  l.add(4);
  l.addAll([5, 6]);
  print(
    '$l ${l.length} ${l.first} ${l.last} ${l.isEmpty} ${l.reversed} ${l.indexOf(2)} ${l.contains(9)}',
  ); // expect: [3, 1, 2, 4, 5, 6] 6 3 6 false (6, 5, 4, 2, 1, 3) 2 false
  l.sort();
  print(l); // expect: [1, 2, 3, 4, 5, 6]
  l.sort((a, b) => b - a);
  print(l); // expect: [6, 5, 4, 3, 2, 1]
  l.insert(1, 50);
  l.insertAll(2, [7, 8]);
  print(l); // expect: [6, 50, 7, 8, 5, 4, 3, 2, 1]
  l.removeAt(0);
  print(l.removeLast()); // expect: 1
  l.remove(50);
  l.removeWhere((x) => x.isOdd);
  print(l); // expect: [8, 4, 2]
  l.addAll(l.toList());
  print(l); // expect: [8, 4, 2, 8, 4, 2]
  l.setRange(0, 2, [9, 10]);
  l.fillRange(2, 3, 0);
  print(l); // expect: [9, 10, 0, 8, 4, 2]
  print(l.sublist(1, 3)); // expect: [10, 0]
  l.length = 2;
  print(l); // expect: [9, 10]
  l.clear();
  print(l); // expect: []
  print(l.isEmpty); // expect: true
  final m = List.generate(10, (i) => i * i);
  print(
    m.map((x) => x + 1).where((x) => x.isEven).toList(),
  ); // expect: [2, 10, 26, 50, 82]
  print(m.fold<int>(0, (a, b) => a + b)); // expect: 285
  print(m.reduce((a, b) => a > b ? a : b)); // expect: 81
  print(m.any((x) => x > 80)); // expect: true
  print(m.every((x) => x > 80)); // expect: false
  print(m.take(3)); // expect: (0, 1, 4)
  print(m.skip(8)); // expect: (64, 81)
  print(m.takeWhile((x) => x < 10)); // expect: (0, 1, 4, 9)
  print(
    m.skipWhile((x) => x < 10).toList(),
  ); // expect: [16, 25, 36, 49, 64, 81]
  print(m.firstWhere((x) => x > 10)); // expect: 16
  print(m.lastWhere((x) => x < 10)); // expect: 9
  print(m.firstWhere((x) => x > 1000, orElse: () => -1)); // expect: -1
  print(m.expand((x) => [x, x]).length); // expect: 20
  print(m.join('/')); // expect: 0/1/4/9/16/25/36/49/64/81
  print(m.asMap()[3]); // expect: 9
  print(m.elementAt(2)); // expect: 4
  print(m.toSet().length); // expect: 10
  print(m.followedBy([1]).last); // expect: 1
  print(m.indexWhere((x) => x == 49)); // expect: 7
  print(m.getRange(2, 4)); // expect: (4, 9)
  print([1, 2] + [3]); // expect: [1, 2, 3]
  print(List.filled(2, 'x')); // expect: [x, x]
  print(List.of(m, growable: false).length); // expect: 10
  print(List<int>.from([1, 2])); // expect: [1, 2]
  print(List.unmodifiable([1])); // expect: [1]
}
