import 'dart:async';

Stream<int> events(Stream<int> source) async* {
  for (var i = 0; i < 2; i++) {
    try {
      yield* source;
    } on StateError {
      yield 9 + i;
    }
  }
  yield* Stream<int>.fromIterable([11, 12]);
}

Future<void> main() async {
  final used = Stream<int>.value(1);
  await used.drain<void>();
  print(await events(used).toList());
  print('done');
}
