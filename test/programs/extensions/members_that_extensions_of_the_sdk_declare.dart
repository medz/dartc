void main() {
  print(<int>[].firstOrNull); // expect: null
  print([3].firstOrNull); // expect: 3
  print([1, 2].lastOrNull); // expect: 2
  print([1, null, 2].nonNulls.toList()); // expect: [1, 2]

  print([1, 2].elementAtOrNull(5)); // expect: null
  Iterable<int> one = [4];
  print(one.singleOrNull); // expect: 4
}
