T choose<T>(bool first, T left, T right) {
  if (first) return left;
  return right;
}

int branch(int value) => choose(value > 0, value + 4, value - 5);

int sum(int count) {
  var result = 0;
  for (var index = 0; index < count; index++) {
    result += index;
  }
  return result;
}

int loop(int count) => sum(count) + 1;

int visits = 0;

int guarded(int value) {
  try {
    if (value < 0) throw value;
    return 12 ~/ value;
  } on int catch (error) {
    if (error == -2) rethrow;
    return -error;
  } finally {
    visits++;
    if (value == 3) throw 99;
  }
}

int exceptions(int value) {
  visits = 0;
  int result;
  try {
    result = guarded(value);
  } on int catch (error) {
    result = error - 20;
  } catch (_) {
    result = -90;
  }
  return result * 10 + visits;
}

Never fail(int value) => throw value;

int neverCall(int value) {
  try {
    fail(value);
  } on int catch (error) {
    return error + 1;
  }
}

T invoke<T>(T Function() action) => action();

int closureThroughCall(int value) => invoke(() => value + 1);

T captured<T>(T value) {
  T action() => value;
  return invoke(action);
}

int closureGeneric(int value) => captured(value);

int closureCells(int value) {
  var current = value;
  int action(int delta, {int divisor = 2}) {
    current += delta;
    if (current < 0) throw current;
    return current ~/ divisor;
  }

  int read() => current;
  try {
    return action(1) + read();
  } on int catch (error) {
    return error - read();
  } finally {
    current++;
  }
}
