import 'effects.dart';

Future<int> sum(Stream<int> source, int mode) async {
  var result = 0;
  try {
    await for (final value in source) {
      try {
        tick(value);
        if (mode == 1 && value == 2) continue;
        if (mode == 2 && value == 2) break;
        if (mode == 3 && value == 2) return result;
        if (mode == 4 && value == 2) throw StateError('body');
        result += value;
      } finally {
        tick(10 + value);
      }
    }
  } catch (_) {
    tick(60);
  } finally {
    tick(70);
  }
  return result;
}

Future<int> collected(Stream<int> source) async {
  final values = [await for (final value in source) value + 1];
  var result = 0;
  for (final value in values) {
    result += value;
  }
  return result;
}

Stream<int> forwarded(Stream<int> source) async* {
  try {
    await for (final value in source) {
      yield value;
    }
  } finally {
    tick(70);
  }
}
