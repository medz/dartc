import 'effects.dart' as effects;

int nestedTransfers(int limit, int stop) {
  var sum = 0;
  outer:
  for (
    var i = effects.tick(0), step = 1;
    effects.tick(i) < limit;
    i += step, effects.tick(10 + i)
  ) {
    var j = 0;
    do {
      final previous = j++;
      sum += effects.tick(i * 10 + j);
      if (stop < sum) break outer;
      if (previous < 1 && i < 2) continue outer;
      if (j < 2) continue;
      if (i < 3) break;
    } while (effects.tick(j) < 3);
    sum += effects.tick(40 + i);
  }
  return sum;
}

int whileTransfers(int limit) {
  var i = 0, sum = 0;
  while (effects.tick(i++) < limit) {
    if (i < 2) continue;
    sum += effects.tick(i);
    if (3 < i) break;
  }
  return sum * 10 + i;
}

int doTransfers(int n, bool stop) {
  var sum = 0;
  do {
    sum += effects.tick(1);
    if (stop) break;
    if (sum < 2) continue;
    sum += effects.tick(2);
  } while (effects.tick(n--) < 4 && 0 < n);
  return n * 10 + sum;
}

int forever(int start, bool stop) {
  var i = 20;
  leave:
  {
    for (i = effects.tick(start); ; i++) {
      if (i < 2) continue;
      if (stop) break leave;
      break;
    }
    i += effects.tick(10);
  }
  return i;
}

int firstIteration(int n) {
  do {
    if (n < 2) return effects.tick(n);
    n--;
  } while (effects.probe(n - 1));
  return n;
}
