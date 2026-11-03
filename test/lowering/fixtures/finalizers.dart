import 'effects.dart' as effects;
import 'functions.dart' show voidResult;

int savedReturn(int n) {
  try {
    if (n > 0) return effects.tick(n++);
    if (n < 0) return effects.tick(2);
    throw 9;
  } finally {
    effects.tick(n + 3);
  }
}

void forwardThroughCleanup(int n) {
  try {
    if (n == 0) return;
    return voidResult(n);
  } finally {
    effects.tick(5);
  }
}

int overrideCompletion(int action, int replace) {
  try {
    try {
      if (action == 0) return effects.tick(1);
      if (action == 1) throw 8;
      effects.tick(action);
    } on int catch (e) {
      if (replace < 0) return e;
      rethrow;
    } finally {
      effects.tick(3);
      // ignore: control_flow_in_finally
      if (replace == 0) return 4;
      if (replace == 1) throw 5;
    }
    return 6;
  } on int catch (e) {
    return e + 10;
  }
}

int loopExits(int n) {
  var sum = 0;
  outer:
  for (var i = 0; i < 3; i++) {
    try {
      for (var j = 0; j < 3; j++) {
        if (j == 0) continue;
        sum += effects.tick(j);
        break;
      }
      if (i == n) continue outer;
      if (i > n) break outer;
      sum += effects.tick(i);
    } finally {
      sum += effects.tick(5 + i);
    }
  }
  return sum;
}

int replaceReturnWithJump(int kind) {
  outer:
  for (var i = 0; i < 2; i++) {
    try {
      try {
        return effects.tick(i + 1);
      } finally {
        effects.tick(2);
        // ignore: control_flow_in_finally
        if (kind == 0) break outer;
        // ignore: control_flow_in_finally
        if (kind == 1) continue outer;
      }
    } finally {
      effects.tick(3);
    }
  }
  return 8;
}

int toCase(int n) {
  switch (n) {
    case 0:
      try {
        continue finish;
      } finally {
        effects.tick(1);
      }
    finish:
    default:
      return effects.tick(2);
  }
}

int leaveTry(bool stop) {
  var n = 1;
  done:
  try {
    if (stop) break done;
    n = 2;
  } finally {
    n += effects.tick(n);
  }
  return n;
}
