// if without else
int? ifWithoutElse() {
  var x = 1;
  if (x > 1) x = 9;
  if (x == 1) x = 4;
  return x;
}

// else if
int? elseIf() {
  var x = 5;
  if (x < 3) {
    x = 0;
  } else if (x < 6) {
    x = 1;
  } else {
    x = 2;
  }
  return x;
}

// both sides leave
int? bothSidesLeave() {
  if (1 > 2) {
    return 1;
  } else {
    return 2;
  }
}

// conditional expressions
int? conditionalExpressions() {
  var x = 3;
  return x > 2 ? (x > 5 ? 1 : 2) : 3;
}

// assignments inside conditions survive
int? assignmentsInsideConditionsSurvive() {
  var x = 0;
  final y = (x = 4) > 3 ? x++ : x--;
  return x * 10 + y;
}

// && and || stop early
int? andStopEarly() {
  var n = 0;
  final a = 1 > 2 && (n += 1) > 0;
  final b = 1 < 2 || (n += 10) > 0;
  final c = 1 < 2 && (n += 100) > 0;
  final d = 1 > 2 || (n += 1000) > 0;
  if (!a && b && c && d) return n;
}

void main() {
  print(ifWithoutElse()); // expect: 4
  print(elseIf()); // expect: 1
  print(bothSidesLeave()); // expect: 2
  print(conditionalExpressions()); // expect: 2
  print(assignmentsInsideConditionsSurvive()); // expect: 54
  print(andStopEarly()); // expect: 1100
}
