// ignore_for_file: await_only_futures

Future<int> accumulated(int count, int seed) async {
  var captured = seed;
  int read() => captured;
  for (var i = 0; i < count; i++) {
    final before = read();
    await i;
    captured = before + i;
  }
  return read();
}

Future<T> nested<T>(T value) async {
  await 0;
  T read() => value;
  return read();
}

Future<int> refined(Object value) async {
  final isInt = value is int;
  await 0;
  if (isInt) {
    return value + 1;
  }
  return 0;
}

Future<Object> handled(Object token) async {
  try {
    try {
      throw token;
    } catch (_) {
      await 0;
      rethrow;
    }
  } catch (error) {
    return error;
  }
}

Iterable<int> iterations(int seed) sync* {
  var value = seed;
  int next() => ++value;
  for (var i = 0; i < 3; i++) {
    yield next();
  }
}

Future<Object> caught(Future<int> event) async {
  try {
    return await event;
  } catch (error) {
    return error;
  }
}
