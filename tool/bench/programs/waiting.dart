// Asynchronous functions and generators.
Future<int> later(int n) async {
  if (n % 3 == 0) await null;
  return n + 1;
}

Stream<int> numbers(int count) async* {
  for (var i = 0; i < count; i++) {
    yield await later(i);
  }
}

Iterable<int> evens(int count) sync* {
  for (var i = 0; i < count; i++) {
    if (i.isEven) yield i;
  }
}

Future<void> main() async {
  var sum = 0;
  for (var i = 0; i < 600000; i++) {
    sum += await later(i);
  }
  print(sum);
  await for (final n in numbers(200000)) {
    sum ^= n;
  }
  print(sum);
  for (final n in evens(4000000)) {
    sum += n;
  }
  print(sum);
}
