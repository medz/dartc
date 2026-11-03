import 'effects.dart' as effects;

int siteLocals(int n) {
  var state = 1;
  try {
    state = effects.tick(n);
    effects.tick(state = 2);
    if (n == 0) throw 7;
    state = effects.tick(n - 2);
  } on int catch (e) {
    state += e;
  } on Error {
    state = 10 + state;
  }
  return effects.tick(state);
}

int atomic(int a, int b, int? last) {
  try {
    (a, b!) = (effects.tick(7), last);
  } on TypeError {
    effects.tick(a);
  }
  return a * 10 + b;
}

Never raiseObject(Object value) => throw value;

int filter(Object value, bool again) {
  try {
    try {
      raiseObject(value);
    } on int catch (e) {
      effects.tick(e);
      if (again) rethrow;
      throw e + 9;
    }
  } on int catch (e) {
    return e;
  } on String {
    return 11;
  }
}

int implicitThrow(Object? value, Object other) {
  try {
    if ((value,) == (other,)) return 5;
    return value as int;
  } on TypeError {
    return 6;
  } on Error {
    return 7;
  }
}

bool sameThrow(Object value) {
  try {
    raiseObject(value);
  } catch (original, trace) {
    try {
      try {
        throw 0;
      } on int {
        effects.tick(1);
      }
      rethrow;
    } catch (again, secondTrace) {
      return original == again && trace == secondTrace;
    }
  }
}
