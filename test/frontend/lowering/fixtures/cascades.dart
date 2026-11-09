import 'effects.dart' as effects;
import 'static_accessors.dart' as accessors;

class Box(var int value, var Box? child) {
  Box self(int mark) {
    effects.tick(mark);
    return this;
  }

  int operator [](int key) => value + effects.tick(key);
  void operator []=(int key, int n) {
    effects.tick(key);
    value = n;
  }

  void set(int n) {
    value = effects.tick(n);
  }
}

int cascade(int n, bool missing) {
  final box = Box(1, null);
  final Box? target = missing ? null : box;
  try {
    final result = target?.self(1)
      ?..value = effects.tick(2)
      ..[effects.tick(3)] += effects.tick(n)
      ..child?.set(effects.tick(4))
      ..self(5).value += 1
      ..value += (Box(7, null)..set(effects.tick(6))).value;
    return result == box ? box.value : -1;
  } catch (_) {
    return box.value * 100;
  }
}

int ordinaryCascade(int n) {
  final box = Box(1, Box(2, null));
  final result = box.self(1)
    ..child!.value = effects.tick(n)
    ..set(effects.tick(3))
    ..value += 1;
  return result.value + box.child!.value;
}

int cascadeThrow(bool missing) {
  final Box? box = missing ? null : Box(1, null);
  try {
    box
      ?..set(throw effects.tick(2))
      // ignore: dead_code
      ..set(effects.tick(3));
  } catch (_) {
    return 7;
  }
  return 8;
}

int callableCascade(int n) {
  int f(int value) => effects.tick(value);
  final result = f..call(n);
  return result(3);
}

int recordCascade(int n) {
  final record = (Box(n, null),);
  final result = record..$1.set(effects.tick(4));
  return result.$1.value;
}

int prefixedAccess(int n) {
  try {
    accessors.value += effects.tick(n);
    accessors.Access.value = effects.tick(n);
    return accessors.callback(effects.tick(n)) + accessors.Access.value;
  } catch (_) {
    return -1;
  }
}
