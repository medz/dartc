// break in each kind
int? breakInEachKind() {
  var n = 0;
  while (true) {
    if (++n > 3) break;
  }
  do {
    if (++n > 6) break;
  } while (true);
  return n;
}

// while
int? caseWhile() {
  var n = 0, i = 0;
  while (i < 5) {
    n += i;
    i++;
  }
  return n;
}

// while that never runs
int? whileThatNeverRuns() {
  var n = 7;
  while (n < 0) n++;
  return n;
}

// do
int? caseDo() {
  var n = 0;
  do {
    n++;
  } while (n < 5);
  return n;
}

// for
int? caseFor() {
  var n = 0;
  for (var i = 0, j = 9; i < j; i++, j--) n += j - i;
  return n;
}

// for with an expression
int? forWithAnExpression() {
  int i, n = 0;
  for (i = 2; i < 3; i++) n += i;
  return n * 10 + i;
}

// for without parts
int? forWithoutParts() {
  var n = 0;
  for (;;) {
    if (++n == 6) break;
  }
  return n;
}

// continue in each kind
int? continueInEachKind() {
  var n = 0;
  for (var i = 0; i < 6; i++) {
    if (i % 2 == 0) continue;
    n += i;
  }
  var j = 0;
  while (j < 6) {
    j++;
    if (j == 3) continue;
    n += 10;
  }
  var k = 0;
  do {
    k++;
    if (k == 2) continue;
    n += 100;
  } while (k < 4);
  return n;
}

// labels
int? caseLabels() {
  var n = 0;
  outer:
  for (var i = 0; i < 5; i++) {
    for (var j = 0; j < 5; j++) {
      if (j == 3) continue outer;
      if (i == 3) break outer;
      n++;
    }
  }
  block:
  {
    n += 100;
    if (n > 50) break block;
    n += 1000;
  }
  return n;
}

// variables of an iteration are fresh
int? variablesOfAnIterationAreFresh() {
  var n = 0;
  for (var i = 0; i < 3; i++) {
    int x;
    if (i == 1) {
      x = 5;
    } else {
      x = 1;
    }
    n += x;
  }
  return n;
}

// swapping needs both old values
int? swappingNeedsBothOldValues() {
  var a = 1, b = 2;
  for (var i = 0; i < 3; i++) {
    final t = a;
    a = b;
    b = t;
  }
  return a * 10 + b;
}

void main() {
  print(breakInEachKind()); // expect: 7
  print(caseWhile()); // expect: 10
  print(whileThatNeverRuns()); // expect: 7
  print(caseDo()); // expect: 5
  print(caseFor()); // expect: 25
  print(forWithAnExpression()); // expect: 23
  print(forWithoutParts()); // expect: 6
  print(continueInEachKind()); // expect: 359
  print(caseLabels()); // expect: 109
  print(variablesOfAnIterationAreFresh()); // expect: 7
  print(swappingNeedsBothOldValues()); // expect: 21
}
